from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / "public/branding/sadesa-mark.png"
out_dir = ROOT / "public/branding"
public_dir = ROOT / "public"
out_dir.mkdir(parents=True, exist_ok=True)

image = Image.open(source).convert("RGBA")
alpha = image.getchannel("A")
if alpha.getbbox() is not None:
    image = image.crop(alpha.getbbox())

# Add a small transparent safe area so the mark does not touch icon edges.
canvas_size = max(image.size)
padded = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
left = (canvas_size - image.width) // 2
upper = (canvas_size - image.height) // 2
padded.alpha_composite(image, (left, upper))

outputs = {
    "sadesa-logo.png": (768, 768),
    "sadesa-icon-192.png": (192, 192),
    "sadesa-icon-512.png": (512, 512),
    "sadesa-apple-touch-icon.png": (180, 180),
    "sadesa-favicon.png": (64, 64),
}
for filename, dimensions in outputs.items():
    width, height = dimensions
    resized = ImageOps.contain(padded, dimensions, Image.Resampling.LANCZOS)
    target = Image.new("RGBA", dimensions, (0, 0, 0, 0))
    target.alpha_composite(resized, ((width - resized.width) // 2, (height - resized.height) // 2))
    target.save(out_dir / filename, format="PNG", optimize=True)

# Keep the conventional public favicon path in sync with the new mark.
icon = Image.open(out_dir / "sadesa-favicon.png").convert("RGBA")
icon.save(public_dir / "favicon.ico", format="ICO", sizes=[(16, 16), (32, 32), (48, 48)])
# PWA plugin includeAssets expects these stable filenames.
for size, filename in ((192, "pwa-192x192.png"), (512, "pwa-512x512.png")):
    Image.open(out_dir / f"sadesa-icon-{size}.png").save(public_dir / filename, format="PNG", optimize=True)

print("Generated:")
for filename in [*outputs.keys(), "../favicon.ico", "../pwa-192x192.png", "../pwa-512x512.png"]:
    print(filename)
