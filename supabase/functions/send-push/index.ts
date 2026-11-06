// notifications 테이블에서 pushed_at 이 비어있는 건을 FCM(HTTP v1)으로 발송한다.
// 호출: pg_cron (5분마다) → x-cron-secret 헤더로 인증.
// 필요한 Secrets: FCM_SERVICE_ACCOUNT (Firebase 서비스계정 JSON 전체), CRON_SECRET
// SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY 는 Supabase 가 자동 주입.
import { createClient } from "jsr:@supabase/supabase-js@2";

const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

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

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return new Response("unauthorized", { status: 401 });
  }

  const { data: rows, error } = await db
    .from("notifications")
    .select("id, title, body, kind, profiles(fcm_token)")
    .is("pushed_at", null)
    .order("id")
    .limit(500);
  if (error) return new Response(error.message, { status: 500 });
  if (!rows?.length) return Response.json({ sent: 0 });

  const token = await accessToken();
  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  let sent = 0, skipped = 0, failed = 0;
  const done: number[] = [];

  for (const n of rows) {
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
  return Response.json({ sent, skipped, failed });
});
