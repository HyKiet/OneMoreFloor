# Pump icons

Created on 2026-10-12 for Pump a Balloon to Space with the built-in image_gen tool.

Eight square PNGs, each 1254 x 1254 pixels, RGBA with a transparent background:

| Tier | Catalog ID | File |
|---|---|---|
| 1 | Hand | HandPump.png |
| 2 | Foot | FootPump.png |
| 3 | Double | DoublePump.png |
| 4 | Compressor | AirCompressor.png |
| 5 | Turbo | TurboCompressor.png |
| 6 | Jet | JetPump.png |
| 7 | Storm | StormPump.png |
| 8 | Hurricane | HurricanePump.png |

Open index.html locally to view every icon at 64, 128, 256, or 384 px on light and dark backgrounds. Preview sizing does not modify the PNGs.

Dark navy outlines, saturated colors and crisp cartoon shading follow the existing Icon collection. All eight depict pump devices; higher tiers use turbine, lightning and vortex details to distinguish their silhouettes.

prompts.json records the exact prompts and reference paths. validation.json records image dimensions, alpha ranges and visible content bounds. Near-invisible generation residue (alpha below 8/255) is excluded from clipping checks; the original generated alpha has been preserved.

Style references come from the existing Icon collection by @gvesster; original usage terms are in ../License.txt. The image tool does not expose model selection or report the actual model identifier.

All eight PNGs were uploaded by the user on 2026-10-12. The supplied IDs are in roblox_asset_ids.json and prompts.json; UI/Core/Icons.luau is the runtime source of truth. Shop and the next-pump goal HUD use these icons.
