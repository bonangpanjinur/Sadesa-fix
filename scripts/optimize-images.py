from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

# Keep originals for rollback and use conservative dimensions suitable for the
# actual UI slots. WebP quality 82 preserves branding/product detail well while
# removing the PNG/JPEG overhead measured by Lighthouse.
TARGETS = {
    ROOT / "public/branding/sadesa-logo.png": {"max_width": 768, "quality": 82},
    ROOT / "src/assets/hero-village.jpg": {"max_width": 1280, "quality": 80},
    ROOT / "src/assets/village-bojong.jpg": {"max_width": 800, "quality": 80},
    ROOT / "src/assets/village-sukamaju.jpg": {"max_width": 800, "quality": 80},
    ROOT / "src/assets/product-anyaman.jpg": {"max_width": 640, "quality": 82},
    ROOT / "src/assets/product-keripik.jpg": {"max_width": 640, "quality": 82},
    ROOT / "src/assets/product-kopi.jpg": {"max_width": 640, "quality": 82},
    ROOT / "src/assets/product-sambal.jpg": {"max_width": 640, "quality": 82},
}

for source, options in TARGETS.items():
    output = source.with_suffix(".webp")
    with Image.open(source) as image:
        image = image.convert("RGB")
        max_width = options["max_width"]
        if image.width > max_width:
            height = round(image.height * max_width / image.width)
            image = image.resize((max_width, height), Image.Resampling.LANCZOS)
        image.save(output, "WEBP", quality=options["quality"], method=6)
        print(f"{source.name}: {source.stat().st_size} -> {output.name}: {output.stat().st_size} ({image.width}x{image.height})")
