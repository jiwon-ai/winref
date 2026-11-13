// notifications 테이블에서 pushed_at 이 비어있는 건을 FCM(HTTP v1)으로 발송한다.
// 호출: pg_cron (5분마다) → x-cron-secret 헤더로 인증.
// 필요한 Secrets: FCM_SERVICE_ACCOUNT (Firebase 서비스계정 JSON 전체), CRON_SECRET
// SUPABASE_URL, SUPABASE_SECRET_KEYS(또는 SUPABASE_SERVICE_ROLE_KEY) 는 Supabase 가 자동 주입.
//
// (선택) 카카오 알림톡: 아래 Secrets 를 모두 넣으면 중요한 알림을 알림톡으로도 보낸다. 없으면 푸시만 보낸다.
//   SOLAPI_API_KEY, SOLAPI_API_SECRET : 솔라피(solapi.com) API 키
//   SOLAPI_PFID        : 솔라피에 연동한 카카오 비즈니스 채널 ID
//   SOLAPI_TEMPLATE_ID : 카카오 심사를 통과한 알림톡 템플릿 ID (변수 #{제목}, #{내용} 사용)
//   SOLAPI_SENDER      : 솔라피에 등록한 발신번호 (알림톡 실패 시 문자 대체 발송용)
//   ALIMTALK_KINDS     : (선택) 알림톡으로 보낼 알림 종류. 기본 selection,competition_d1,refresher,course_deadline
import { createClient } from "jsr:@supabase/supabase-js@2";

const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
// 새 Secret 키(SUPABASE_SECRET_KEYS)를 우선 쓰고, 없으면 레거시 service role 키 사용
const secretKey = (() => {
  try {
    const d = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    return (d.default ?? Object.values(d)[0]) as string | undefined;
  } catch { return undefined; }
})() || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(Deno.env.get("SUPABASE_URL")!, secretKey);

const b64url = (b: ArrayBuffer | Uint8Array | string) => {
  const bytes = typeof b === "string" ? new TextEncoder().encode(b) : new Uint8Array(b as ArrayBuffer);
  let s = "";
  for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

// 서비스계정 키로 Google OAuth 액세스 토큰 발급 (JWT bearer grant)
async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = (sa.private_key as string).replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claim}`));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claim}.${b64url(sig)}`,
    }),
  });
  if (!res.ok) throw new Error(`OAuth ${res.status}: ${await res.text()}`);
  return (await res.json()).access_token;
}

// ---------- 카카오 알림톡 (솔라피) ----------
const solapi = {
  key: Deno.env.get("SOLAPI_API_KEY"),
  secret: Deno.env.get("SOLAPI_API_SECRET"),
  pfId: Deno.env.get("SOLAPI_PFID"),
  templateId: Deno.env.get("SOLAPI_TEMPLATE_ID"),
  sender: Deno.env.get("SOLAPI_SENDER"),
};
const alimtalkOn = Object.values(solapi).every((v) => !!v);
const alimtalkKinds = (Deno.env.get("ALIMTALK_KINDS") ?? "selection,competition_d1,refresher,course_deadline").split(",").map((s) => s.trim());

// 솔라피 인증 헤더: HMAC-SHA256(date + salt, API Secret)
async function solapiAuth(): Promise<string> {
  const date = new Date().toISOString();
  const salt = crypto.randomUUID().replaceAll("-", "");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(solapi.secret!), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(date + salt));
  const hex = [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `HMAC-SHA256 apiKey=${solapi.key}, date=${date}, salt=${salt}, signature=${hex}`;
}

async function sendAlimtalk(phone: string, title: string, body: string): Promise<boolean> {
  const res = await fetch("https://api.solapi.com/messages/v4/send", {
    method: "POST",
    headers: { Authorization: await solapiAuth(), "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        to: phone,
        from: solapi.sender,
        kakaoOptions: {
          pfId: solapi.pfId,
          templateId: solapi.templateId,
          variables: { "#{제목}": title, "#{내용}": body },
        },
      },
    }),
  });
  if (!res.ok) console.error("alimtalk", res.status, await res.text());
  return res.ok;
}

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return new Response("unauthorized", { status: 401 });
  }

  const { data: rows, error } = await db
    .from("notifications")
    .select("id, title, body, kind, profiles(fcm_token, phone)")
    .is("pushed_at", null)
    .order("id")
    .limit(500);
  if (error) return new Response(error.message, { status: 500 });
  if (!rows?.length) return Response.json({ sent: 0 });

  const token = await accessToken();
  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  let sent = 0, skipped = 0, failed = 0;
  const done: number[] = [];
  let talk = 0;
  const talked: number[] = [];

  for (const n of rows) {
    // 알림톡: 설정돼 있고, 중요한 알림이며, 휴대폰 번호가 있는 회원에게만 (푸시와 별개로 발송)
    // deno-lint-ignore no-explicit-any
    const phone = (n as any).profiles?.phone as string | null;
    if (alimtalkOn && phone && alimtalkKinds.includes(n.kind)) {
      try {
        if (await sendAlimtalk(phone, n.title, n.body ?? "")) { talk++; talked.push(n.id); }
      } catch (e) {
        console.error("alimtalk", e);
      }
    }
    // deno-lint-ignore no-explicit-any
    const fcm = (n as any).profiles?.fcm_token as string | null;
    if (!fcm) { skipped++; done.push(n.id); continue; } // 토큰 없는 회원은 앱 알림함으로만 확인
    const res = await fetch(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token: fcm,
          notification: { title: n.title, body: n.body ?? "" },
          data: { kind: n.kind, id: String(n.id) },
          android: { priority: "HIGH" },
        },
      }),
    });
    if (res.ok) { sent++; done.push(n.id); }
    else if (res.status === 404 || res.status === 400) { failed++; done.push(n.id); } // 만료·잘못된 토큰: 재시도 안 함
    else { failed++; } // 일시 오류는 다음 실행 때 재시도
  }

  if (done.length) {
    await db.from("notifications").update({ pushed_at: new Date().toISOString() }).in("id", done);
  }
  if (talked.length) {
    await db.from("notifications").update({ alimtalk_at: new Date().toISOString() }).in("id", talked);
  }
  return Response.json({ sent, skipped, failed, alimtalk: talk });
});
