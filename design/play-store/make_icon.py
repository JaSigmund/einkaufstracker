"""Erzeugt das Einkaufstracker-App-Icon (Play Store + Android-Mipmaps) programmatisch mit Pillow.
Motiv: Einkaufstasche mit Haken (Ueberblick/erledigt) auf Markenfarbe (Theme-Seed #2E7D32).
Nicht Teil der App selbst, nur ein einmaliges Design-Werkzeug -- Ausgaben liegen neben diesem Skript
(design/play-store/), die Launcher-Icons landen in app/android/app/src/main/res/.
Aufruf (aus beliebigem Ordner): python design/play-store/make_icon.py   (benoetigt: pip install pillow)
"""
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

GREEN = (46, 125, 50, 255)       # #2E7D32, Theme-Seed
GREEN_DARK = (27, 94, 32, 255)   # #1B5E20, Schattierung
WHITE = (255, 255, 255, 255)
SIZE = 1024


def draw_icon(size: int) -> Image.Image:
    scale = size / SIZE
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Hintergrund: abgerundetes Quadrat in der Markenfarbe
    radius = int(180 * scale)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=GREEN)

    def s(*vals):
        return tuple(v * scale for v in vals)

    # Henkel der Tasche: zwei Boegen
    handle_w = 40 * scale
    d.arc(s(320, 260, 520, 460), start=180, end=360, fill=WHITE, width=int(handle_w))
    d.arc(s(504, 260, 704, 460), start=180, end=360, fill=WHITE, width=int(handle_w))

    # Taschenkoerper: Trapez, unten breiter
    bag = [s(280, 420), s(744, 420), s(800, 820), s(224, 820)]
    d.polygon(bag, fill=WHITE)

    # Falz-Linie mittig auf der Tasche (dezent, in Markenfarbe)
    d.line([s(300, 460), s(724, 460)], fill=GREEN, width=int(10 * scale))

    # Haken-Kreis unten rechts (Ueberblick/erledigt), Kreis in dunklerem Gruen mit weissem Haken
    cx, cy, r = 800 * scale, 800 * scale, 170 * scale
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GREEN_DARK, outline=WHITE, width=int(14 * scale))
    check = [s(730, 800), s(780, 850), s(880, 730)]
    d.line(check, fill=WHITE, width=int(36 * scale), joint="curve")

    return img


if __name__ == "__main__":
    master = draw_icon(SIZE)
    master.save(HERE / "icon_master_1024.png")

    # Play-Store-Icon: 512x512, kein transparenter Rand
    master.resize((512, 512), Image.LANCZOS).save(HERE / "icon_playstore_512.png")

    # Android-Mipmaps (Launcher-Icon je Dichte)
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, px in densities.items():
        out = ROOT / "app" / "android" / "app" / "src" / "main" / "res" / folder / "ic_launcher.png"
        master.resize((px, px), Image.LANCZOS).save(out)
        print(f"geschrieben: {out} ({px}x{px})")

    print("fertig")
