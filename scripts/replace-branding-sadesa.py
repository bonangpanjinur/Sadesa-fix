from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Branding/display files only. Technical package names, repository paths,
# database keys, IndexedDB names, and historical identifiers are intentional.
PATHS = [
    "src",
    "public",
    "index.html",
    "vite.config.ts",
    "README.md",
    "CHANGELOG.md",
    "docs",
    "archive/supabase/migrations_consolidated",
    "archive/supabase/migrations",
    "supabase/bootstrap",
]

REPLACEMENTS = (
    ("DesaMart", "SaDesa"),
    ("Desa Mart", "SaDesa"),
)

TARGETED_REPLACEMENTS = (
    ("https://desamart.id", "https://sadesa.id"),
    ("support@desamart.id", "support@sadesa.id"),
    ("admin@desamart.id", "admin@sadesa.id"),
    ("admin@desamart.app", "admin@sadesa.id"),
    ("template_produk_desamart.csv", "template_produk_sadesa.csv"),
)

changed = []
for relative in PATHS:
    target = ROOT / relative
    candidates = [target] if target.is_file() else [p for p in target.rglob("*") if p.is_file()]
    for path in candidates:
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        updated = text
        for old, new in REPLACEMENTS + TARGETED_REPLACEMENTS:
            updated = updated.replace(old, new)
        if updated != text:
            path.write_text(updated, encoding="utf-8")
            changed.append(path.relative_to(ROOT).as_posix())

# The live public hostname is part of CORS configuration, not a database
# identifier. Keep provider email addresses unchanged until the mail domain is
# explicitly confirmed by the owner.
for path in (ROOT / "supabase/functions").rglob("*.ts"):
    text = path.read_text(encoding="utf-8")
    updated = text
    for old, new in TARGETED_REPLACEMENTS:
        updated = updated.replace(old, new)
    if updated != text:
        path.write_text(updated, encoding="utf-8")
        changed.append(path.relative_to(ROOT).as_posix())

print(f"Updated {len(changed)} files")
for item in sorted(set(changed)):
    print(item)
