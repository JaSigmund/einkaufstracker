"""Erzeugt die Play-Store-Feature-Grafik (1024x500) mit Icon, App-Namen und Slogan.

Braucht icon_master_1024.png (erzeugt von make_icon.py) und die Windows-Schriften Arial/Segoe UI.
Aufruf (aus beliebigem Ordner): python design/play-store/make_feature_graphic.py   (benoetigt: pip install pillow)
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent

W, H = 1024, 500
GREEN = (46, 125, 50, 255)
GREEN_DARK = (27, 94, 32, 255)
WHITE = (255, 255, 255, 255)

img = Image.new("RGBA", (W, H), GREEN)
d = ImageDraw.Draw(img)

# Dezenter diagonaler Farbverlauf-Effekt: dunklerer Streifen unten rechts
d.polygon([(W * 0.55, H), (W, H), (W, H * 0.35)], fill=GREEN_DARK)

# Icon einfuegen (links)
icon = Image.open(HERE / "icon_master_1024.png").resize((360, 360), Image.LANCZOS)
img.paste(icon, (60, 70), icon)

# Text (rechts vom Icon)
title_font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 72)
subtitle_font = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 34)

d.text((460, 170), "Einkaufstracker", font=title_font, fill=WHITE)
d.text((462, 260), "Bons scannen. Ausgaben & Inventar\nim Blick behalten.", font=subtitle_font, fill=WHITE, spacing=12)

out = HERE / "feature_graphic_1024x500.png"
img.convert("RGB").save(out)
print(f"fertig: {out}")
