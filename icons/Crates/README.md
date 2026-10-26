# Crates icons

Created on 2026-10-12 for Pump a Balloon to Space.

All images are original generated PNG outputs preserved in RGBA at 1254 x 1254 pixels (1:1), with transparent backgrounds. validation.json checks dimensions, alpha and visible content bounds; near-invisible residue below alpha 8/255 is ignored for clipping checks. Original alpha has been preserved.

The built-in image_gen tool was used; its underlying model identifier and model selector are not exposed. prompts.json records every prompt and style reference. Existing Icon style references come from @gvesster; see ../License.txt for the source collection's terms.

Open index.html locally to compare icons at 64, 128, 192, 256 or 384 pixels, on light or dark backgrounds. Preview sizing does not modify the PNGs.

The user uploaded reduced-resolution versions on 2026-10-12. roblox_asset_ids.json and prompts.json contain the current uploaded IDs; UI/Core/Icons.luau is the runtime source of truth. The local source PNGs remain unchanged. Cargo/Crates menus, equipped slots, crate reveal, and flight result UI use the uploaded images.

| Catalog ID | Name | File |
|---|---|---|
| Basic | Basic Crate | BasicCrate.png |
| Sky | Sky Crate | SkyCrate.png |
| Space | Space Crate | SpaceCrate.png |
| Cosmic | Cosmic Crate | CosmicCrate.png |

CosmicCrate.png uses a second image_gen framing pass to keep the full orbit inside the canvas. The framing prompt is recorded in prompts.json.
