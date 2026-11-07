"""WINREF ACADEMY 로고 원본(brand_src/)에서 앱 에셋·아이콘·스토어 그래픽을 만든다.
실행: python3 tools/make_icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "brand_src"
BLUE = (74, 144, 226)        # 로고 배경색 #4A90E2
BLUE_DEEP = (37, 96, 172)    # 앱 주색 #2560AC
WHITE = (255, 255, 255)
KR = "/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc"
KR_REG = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"


def alpha_from_blue_bg(path: str) -> Image.Image:
    """파란 배경 위 흰 글자/도형 → 흰색 + 투명 배경 (안티앨리어싱 유지)"""
    im = Image.open(SRC / path).convert("RGB")
    r = im.split()[0]
    bg = BLUE[0]
    a = r.point(lambda v: 0 if v < bg + 25 else min(255, int((v - bg) * 255 / (255 - bg))))
    out = Image.new("RGBA", im.size, WHITE + (0,))
    out.putalpha(a)
    return out.crop(out.getbbox())


def snowflake_mask() -> Image.Image:
    """흰 배경 위 파란 눈꽃 → 알파 마스크 (L)"""
    im = Image.open(SRC / "snowflake_blue_on_white.jpg").convert("RGB")
    r = im.split()[0]
    m = r.point(lambda v: 0 if v > 235 else min(255, int((255 - v) * 255 / (255 - 55))))
    return m.crop(m.getbbox())


def colored(mask: Image.Image, color, size: int) -> Image.Image:
    m = mask.copy()
    m.thumbnail((size, size), Image.LANCZOS)
    out = Image.new("RGBA", m.size, color + (0,))
    out.putalpha(m)
    return out


def icon(mask: Image.Image, size: int, radius_ratio: float = 0.18, pad: float = 0.2) -> Image.Image:
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * radius_ratio), fill=BLUE)
    flake = colored(mask, WHITE, int(s * (1 - 2 * pad)))
    img.alpha_composite(flake, ((s - flake.width) // 2, (s - flake.height) // 2))
    return img.resize((size, size), Image.LANCZOS)


def main():
    mask = snowflake_mask()

    # 앱 안에서 쓰는 로고
    assets = ROOT / "app/assets/brand"
    assets.mkdir(parents=True, exist_ok=True)
    colored(mask, WHITE, 512).save(assets / "snowflake_white.png")
    colored(mask, BLUE, 512).save(assets / "snowflake_blue.png")
    lockup = alpha_from_blue_bg("lockup_on_blue.jpg")
    lockup.thumbnail((900, 900), Image.LANCZOS)
    lockup.save(assets / "lockup_white.png")
    wordmark = alpha_from_blue_bg("wordmark_tagline_on_blue.jpg")
    wordmark.save(assets / "wordmark_white.png")

    # 런처 아이콘 (안드로이드·웹)
    res = ROOT / "app/android/app/src/main/res"
    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        icon(mask, px).save(res / f"mipmap-{folder}/ic_launcher.png")
    web = ROOT / "app/web"
    icon(mask, 192).save(web / "icons/Icon-192.png")
    icon(mask, 512).save(web / "icons/Icon-512.png")
    icon(mask, 192, 0.0, 0.26).save(web / "icons/Icon-maskable-192.png")
    icon(mask, 512, 0.0, 0.26).save(web / "icons/Icon-maskable-512.png")
    icon(mask, 32, 0.18, 0.12).save(web / "favicon.png")

    # Play 스토어 그래픽
    store = ROOT / "store"
    store.mkdir(exist_ok=True)
    icon(mask, 512, 0.0).convert("RGB").save(store / "icon-512.png")
    fg = Image.new("RGB", (1024, 500), BLUE)
    flake = colored(mask, WHITE, 230)
    fg.paste(flake, (95, (500 - flake.height) // 2 - 10), flake)
    wm = wordmark.copy()
    wm.thumbnail((590, 200), Image.LANCZOS)
    fg.paste(wm, (380, 150), wm)
    d = ImageDraw.Draw(fg)
    d.text((384, 150 + wm.height + 22), "스포츠 인재은행 · 교육 · 대회 · 심판 활동이력", font=ImageFont.truetype(KR, 30), fill=WHITE)
    d.text((1024 - 24, 500 - 22), "사회적기업 창업지원사업", font=ImageFont.truetype(KR_REG, 18),
           fill=(225, 238, 252), anchor="rs")
    fg.save(store / "feature-graphic-1024x500.png")


if __name__ == "__main__":
    main()
