"""Package existing/generated art; preserve native alpha. No art is drawn here."""
from pathlib import Path
from collections import Counter
import csv
import hashlib
import json
import math
import shutil
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[2]
PRODUCTS = [
    "ExtraLife", "ExtraLife2", "ExtraLife3", "BlessElevator", "CurseElevator",
    "GoldenElevator", "CashSmall", "CashMedium", "CashLarge", "VIP",
    "DoubleCash", "LuckyBellhop", "StarterPack",
]
ALIASES = {"ExtraLife2": "ExtraLife", "ExtraLife3": "ExtraLife"}
THUMBNAILS = ["TN_A_Risk", "TN_B_Cube", "TN_C_Curse"]
SIZES = {"icons": 512, "ui256": 256, "small64": 64}
NAMES = {
    "ExtraLife": "Extra Life / B1-9", "ExtraLife2": "Extra Life / B10-19",
    "ExtraLife3": "Extra Life / B20+", "BlessElevator": "Bless the Elevator",
    "CurseElevator": "Curse the Elevator", "GoldenElevator": "Golden Elevator",
    "CashSmall": "Cash Small", "CashMedium": "Cash Medium", "CashLarge": "Cash Large",
    "VIP": "VIP", "DoubleCash": "Double Cash", "LuckyBellhop": "Lucky Bellhop",
    "StarterPack": "Starter Pack",
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def export_icon(source, size):
    """Register and resize one cutout inside a circular upload safe area."""
    original = Image.open(source).convert("RGBA")
    alpha = np.asarray(original.getchannel("A"))
    yy, xx = np.nonzero(alpha > 16)
    if not len(xx):
        raise ValueError(f"Empty icon: {source}")
    bbox = original.getchannel("A").getbbox()
    crop = original.crop(bbox)
    cx, cy = (bbox[0] + bbox[2] - 1) / 2, (bbox[1] + bbox[3] - 1) / 2
    radius = float(np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2).max())
    scale = min(size * 0.86 / max(crop.size), size * 0.43 / radius)
    dims = tuple(max(1, round(n * scale)) for n in crop.size)
    # Resize premultiplied alpha to prevent white/dark matte fringes.
    resized = crop.convert("RGBa").resize(dims, Image.Resampling.LANCZOS).convert("RGBA")
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(resized, ((size - dims[0]) // 2, (size - dims[1]) // 2))
    return canvas


def validate_icon(path):
    with Image.open(path) as im:
        im.load()
        if im.mode != "RGBA" or im.width != im.height:
            raise ValueError(f"Not a square RGBA PNG: {path}")
        alpha = np.asarray(im.getchannel("A"))
        corners = [int(alpha[0, 0]), int(alpha[0, -1]), int(alpha[-1, 0]), int(alpha[-1, -1])]
        border = np.concatenate((alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1]))
        yy, xx = np.nonzero(alpha > 16)
        center = (im.width - 1) / 2
        radius = float(np.sqrt((xx - center) ** 2 + (yy - center) ** 2).max())
        if alpha.min() != 0 or alpha.max() != 255 or max(corners) != 0 or border.max() != 0:
            raise ValueError(f"Alpha or outer margin failure: {path}")
        if radius > im.width * 0.47:
            raise ValueError(f"Circular safe area failure: {path}")
        return {
            "path": str(path.relative_to(BASE)), "size": list(im.size), "mode": im.mode,
            "transparent_fraction": round(float((alpha == 0).mean()), 4),
            "corner_alpha": corners, "outer_border_alpha_max": int(border.max()),
            "opaque_radius_fraction": round(radius / im.width, 4),
            "bytes": path.stat().st_size, "sha256": sha256(path),
        }


def font(size, bold=False):
    path = Path("C:/Windows/Fonts") / ("arialbd.ttf" if bold else "arial.ttf")
    return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default()


def checker(size, a=(234, 235, 239), b=(214, 217, 225), tile=12):
    im = Image.new("RGB", size, a)
    d = ImageDraw.Draw(im)
    for y in range(0, size[1], tile):
        for x in range(0, size[0], tile):
            if (x // tile + y // tile) % 2:
                d.rectangle((x, y, x + tile - 1, y + tile - 1), fill=b)
    return im


def preview_products():
    sheet = Image.new("RGB", (1280, 1420), (20, 23, 39))
    d = ImageDraw.Draw(sheet)
    d.text((30, 18), "ONE MORE FLOOR / OUTLINED ICONS v3", font=font(30, True), fill="white")
    d.text((30, 60), "Transparent cutouts. Preview backgrounds are not part of the PNG files.", font=font(18), fill=(180, 190, 210))
    for i, key in enumerate(PRODUCTS):
        x, y = 20 + i % 4 * 315, 105 + i // 4 * 325
        back = checker((290, 230))
        icon = Image.open(BASE / "ui256" / f"{key}.png").convert("RGBA")
        icon.thumbnail((216, 216), Image.Resampling.LANCZOS)
        back.paste(icon, ((290 - icon.width) // 2, (230 - icon.height) // 2), icon)
        sheet.paste(back, (x, y))
        d.text((x + 6, y + 241), NAMES[key], font=font(19, True), fill="white")
        small = Image.open(BASE / "small64" / f"{key}.png")
        sheet.paste(small, (x + 5, y + 270), small)
        d.text((x + 78, y + 285), "64px / native alpha", font=font(15), fill=(160, 175, 199))
    sheet.save(BASE / "previews" / "product-icons-overview.jpg", quality=94)

    # Same exports on a light and a dark surface, at actual 64px size.
    im = Image.new("RGB", (1000, 450), (245, 246, 249))
    dd = ImageDraw.Draw(im)
    dd.rectangle((0, 225, 1000, 450), fill=(13, 15, 31))
    dd.text((20, 12), "LIGHT / 64px", font=font(20, True), fill=(4, 4, 53))
    dd.text((20, 237), "DARK / 64px", font=font(20, True), fill="white")
    for row, y0 in enumerate((58, 283)):
        for i, key in enumerate(PRODUCTS):
            x, y = 18 + i % 7 * 140, y0 + i // 7 * 77
            icon = Image.open(BASE / "small64" / f"{key}.png")
            im.paste(icon, (x, y), icon)
            dd.text((x + 69, y + 20), key[:10], font=font(10), fill=(30, 35, 60) if row == 0 else (210, 220, 238))
    im.save(BASE / "previews" / "light-dark-64px.jpg", quality=95)


def preview_comparison():
    references = [
        (ROOT / "icons/Main/Heart/256px/Heart 1st Outline 256px.png", "ExtraLife", "Heart -> Extra Life"),
        (ROOT / "icons/Item/Shield/256px/Shield 1st Outline 256px.png", "BlessElevator", "Shield -> Bless"),
        (ROOT / "icons/Currency/Coin/256px/Golden Coin 1st Outline 256px.png", "DoubleCash", "Coin -> Double Cash"),
        (ROOT / "icons/Item/Crown/256px/Crown 1st Outline 256px.png", "VIP", "Crown -> VIP (reused)"),
    ]
    sheet = Image.new("RGB", (1100, 1060), (225, 228, 235))
    d = ImageDraw.Draw(sheet)
    d.text((25, 15), "SOURCE REFERENCES / PRODUCTION EXPORTS", font=font(28, True), fill=(4, 4, 53))
    d.text((160, 62), "icons/ reference", font=font(20), fill=(4, 4, 53))
    d.text((695, 62), "v3 export", font=font(20), fill=(4, 4, 53))
    for i, (src, key, label) in enumerate(references):
        y = 105 + i * 235
        for x, p in [(165, src), (705, BASE / "ui256" / f"{key}.png")]:
            icon = Image.open(p).convert("RGBA")
            icon.thumbnail((200, 200), Image.Resampling.LANCZOS)
            sheet.paste(icon, (x + (200 - icon.width) // 2, y + (200 - icon.height) // 2), icon)
        d.text((420, y + 80), label, font=font(17), fill=(4, 4, 53))
    sheet.save(BASE / "previews" / "reference-vs-v3.jpg", quality=95)


def preview_thumbnails():
    out = Image.new("RGB", (1160, 1060), (13, 15, 31))
    d = ImageDraw.Draw(out)
    for i, key in enumerate(THUMBNAILS):
        im = Image.open(BASE / "thumbnails" / f"{key}_1920x1080.jpg")
        large = im.resize((560, 315), Image.Resampling.LANCZOS)
        y = 20 + i * 345
        out.paste(large, (20, y))
        out.paste(im.resize((320, 180), Image.Resampling.LANCZOS), (620, y + 45))
        out.paste(im.resize((160, 90), Image.Resampling.LANCZOS), (970, y + 95))
        d.text((620, y + 10), key + " / 320px and 160px", font=font(18, True), fill="white")
    out.save(BASE / "previews" / "thumbnails-overview.jpg", quality=93)


def main():
    for folder in [*SIZES, "previews", "thumbnails"]:
        (BASE / folder).mkdir(exist_ok=True)
    provenance = json.loads((BASE / "prompts/generation-log.json").read_text(encoding="utf-8"))
    by_key = {x["key"]: x for x in provenance["assets"]}
    uploaded_path = BASE / "roblox_asset_ids.json"
    uploaded = json.loads(uploaded_path.read_text(encoding="utf-8"))["images"] if uploaded_path.exists() else {}
    with (ROOT / "docs/audit-evidence/product-art-manifest.csv").open(encoding="utf-8", newline="") as f:
        commerce = {r["key"]: r for r in csv.DictReader(f)}
    checks, assets = [], []
    for key in PRODUCTS + ["GameIcon"]:
        source_key = ALIASES.get(key, key)
        source = BASE / "source" / f"{source_key}.png"
        if not source.exists():
            raise FileNotFoundError(source)
        native = Image.open(source)
        files = {}
        for folder, size in SIZES.items():
            dest = BASE / folder / f"{key}.png"
            export_icon(source, size).save(dest, optimize=True)
            checks.append(validate_icon(dest))
            files[folder] = str(dest.relative_to(BASE))
        assets.append({
            "key": key, "role": "game_icon" if key == "GameIcon" else "product_icon",
            "source": str(source.relative_to(BASE)), "source_size": list(native.size),
            "origin": by_key[source_key]["origin"], "source_library_path": by_key[source_key]["source"] if by_key[source_key]["origin"] == "existing_user_library" else None,
            "shared_artwork_with": source_key if key in ALIASES else None,
            "commerce_id": commerce.get(key, {}).get("commerce_id"),
            "uploaded_image_asset_id": uploaded.get(key), "files": files,
        })
    for key in THUMBNAILS:
        source = BASE / "source" / f"{key}.png"
        with Image.open(source) as im:
            native_size = list(im.size)
            export = ImageOps.fit(im.convert("RGB"), (1920, 1080), Image.Resampling.LANCZOS)
            dest = BASE / "thumbnails" / f"{key}_1920x1080.jpg"
            export.save(dest, quality=95, subsampling=0, optimize=True)
        if dest.stat().st_size >= 3_000_000:
            raise ValueError(f"Thumbnail exceeds upload target: {dest}")
        assets.append({"key": key, "role": "thumbnail", "origin": "generated_builtin", "source": str(source.relative_to(BASE)), "source_size": native_size, "file": str(dest.relative_to(BASE)), "size": [1920, 1080], "bytes": dest.stat().st_size, "sha256": sha256(dest)})
    manifest = {
        "date": "2026-10-25", "version": 3,
        "style": "2D outlined cel-shaded, based directly on icons/ references",
        "generator": "built-in image_gen; model not exposed", "assets": assets,
        "notes": ["13 product files use 11 distinct artworks; ExtraLife tiers intentionally share one artwork.", "VIP and StarterPack reuse original 256px library art; 512px is an upscale, not a new native high-resolution drawing.", "Cash packs reuse the user's existing transparent CoinPacks artwork.", "Native icon alpha preserved; processing only registers/resizes assets and makes inspection previews.", "Uploaded IDs come from the owner's Asset Manager screenshot; see studio_validation.json for runtime integration verification. Dashboard icons and live publication are separate from UI image bindings."],
    }
    (BASE / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    (BASE / "validation.json").write_text(json.dumps({"icon_exports": checks, "icon_export_count": len(checks), "product_count": len(PRODUCTS), "thumbnail_count": len(THUMBNAILS), "automated_file_checks": "pass", "scope": "File size, dimensions, native alpha, margins and circular safe area. Visual style is manually inspected, not a mathematical guarantee."}, indent=2), encoding="utf-8")
    shutil.copyfile(ROOT / "icons/License.txt", BASE / "SOURCE_ICON_LICENSE.txt")
    preview_products()
    preview_comparison()
    preview_thumbnails()
    bundle = BASE / "OneMoreFloor_Marketing_v3.zip"
    include = [*SIZES, "thumbnails", "previews", "prompts"]
    with zipfile.ZipFile(bundle, "w", zipfile.ZIP_DEFLATED) as z:
        for folder in include:
            for path in sorted((BASE / folder).rglob("*")):
                if path.is_file():
                    z.write(path, path.relative_to(BASE))
        for name in ["manifest.json", "validation.json", "README.vi.md", "style-contract.vi.md", "SOURCE_ICON_LICENSE.txt", "roblox_asset_ids.json", "studio_validation.json"]:
            path = BASE / name
            if path.exists():
                z.write(path, name)
    print(json.dumps({"products": len(PRODUCTS), "distinct_product_artworks": len(set(ALIASES.get(k, k) for k in PRODUCTS)), "icon_exports": len(checks), "thumbnails": len(THUMBNAILS), "bundle": str(bundle), "bundle_bytes": bundle.stat().st_size}, indent=2))


if __name__ == "__main__":
    main()
