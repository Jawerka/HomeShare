from pathlib import Path
import io
import cairosvg
from PIL import Image

root = Path(r"d:\Documents\Projects\apps\HomeShare\apps\homeshare")
svg = (root / "assets/icon/homeshare_icon.svg").read_bytes()


def render(size: int) -> Image.Image:
    png = cairosvg.svg2png(bytestring=svg, output_width=size, output_height=size)
    return Image.open(io.BytesIO(png)).convert("RGBA")


master = render(512)
master.save(root / "assets/icon/homeshare_icon_512.png")
render(256).save(root / "assets/tray_icon.png")

mip = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
res = root / "android/app/src/main/res"
for folder, size in mip.items():
    out = res / folder / "ic_launcher.png"
    render(size).save(out)
    print("wrote", out, size)

draw = res / "drawable"
draw.mkdir(exist_ok=True)
canvas = Image.new("RGBA", (432, 432), (248, 250, 252, 255))
glyph = render(312)
ox = (432 - 312) // 2
oy = (432 - 312) // 2
canvas.paste(glyph, (ox, oy), glyph)
canvas.save(draw / "ic_launcher_foreground.png")
Image.new("RGBA", (432, 432), (248, 250, 252, 255)).save(
    draw / "ic_launcher_background.png"
)

ico_sizes = [16, 24, 32, 48, 64, 128, 256]
ico_images = [render(s) for s in ico_sizes]
ico_path = root / "windows/runner/resources/app_icon.ico"
ico_images[0].save(
    ico_path,
    format="ICO",
    sizes=[(im.width, im.height) for im in ico_images],
    append_images=ico_images[1:],
)
tray_ico = root / "assets/tray_icon.ico"
ico_images[0].save(
    tray_ico,
    format="ICO",
    sizes=[(im.width, im.height) for im in ico_images[:5]],
    append_images=ico_images[1:5],
)
print("wrote", ico_path)
print("wrote", tray_ico)
print("done")
