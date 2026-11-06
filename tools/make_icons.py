"""앱 아이콘·스토어 그래픽 생성 (남색 + 골드 W). 실행: python3 tools/make_icons.py"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
NAVY, GOLD, IVORY = (20, 33, 61), (176, 141, 87), (247, 243, 234)
SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
KR = "/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc"


def icon(size: int, radius_ratio: float = 0.0, pad: float = 0.0) -> Image.Image:
    s = size * 4  # 4배로 그리고 축소 (안티앨리어싱)
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * radius_ratio), fill=NAVY)
    inner = s * (1 - 2 * pad)
    f = ImageFont.truetype(SERIF, int(inner * 0.58))
    box = d.textbbox((0, 0), "W", font=f)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text(((s - w) / 2 - box[0], (s - h) / 2 - box[1] - s * 0.03), "W", font=f, fill=GOLD)
    lw = int(inner * 0.22)
    y = int(s / 2 + h / 2 + s * 0.04)
    d.rectangle([(s - lw) // 2, y, (s + lw) // 2, y + max(4, s // 120)], fill=GOLD)
    return img.resize((size, size), Image.LANCZOS)


def main():
    res = ROOT / "app/android/app/src/main/res"
    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        icon(px, 0.18).save(res / f"mipmap-{folder}/ic_launcher.png")
    web = ROOT / "app/web"
    icon(192, 0.18).save(web / "icons/Icon-192.png")
    icon(512, 0.18).save(web / "icons/Icon-512.png")
    icon(192, 0.0, 0.1).save(web / "icons/Icon-maskable-192.png")
    icon(512, 0.0, 0.1).save(web / "icons/Icon-maskable-512.png")
    icon(32, 0.18).save(web / "favicon.png")

    store = ROOT / "store"
    store.mkdir(exist_ok=True)
    icon(512, 0.0).convert("RGB").save(store / "icon-512.png")  # Play: 512x512, 32bit PNG

    fg = Image.new("RGB", (1024, 500), NAVY)  # Play 그래픽 이미지 1024x500
    d = ImageDraw.Draw(fg)
    fg.paste(icon(200, 0.18), (90, 150), icon(200, 0.18))
    d.text((340, 160), "WINREF ACADEMY", font=ImageFont.truetype(SERIF, 54), fill=IVORY)
    d.rectangle([342, 238, 402, 241], fill=GOLD)
    d.text((340, 262), "스포츠 인재은행", font=ImageFont.truetype(KR, 46), fill=GOLD)
    d.text((340, 330), "교육 · 대회 · 심판 지원 · 활동이력", font=ImageFont.truetype(KR, 26), fill=(185, 192, 208))
    fg.save(store / "feature-graphic-1024x500.png")


if __name__ == "__main__":
    main()
