# Premium illustrations — 14/10/2026

Seven illustrations in the existing Sky Sticker style: 2x Coins, Smart Pump, +1 Cargo Slot, VIP, Lucky Crates, Offline Earnings and Wind Storm. Six newly generated with the built-in imagegen tool; Smart Pump reuses the verified artwork from `Icon/SkyProgression` and its existing Roblox asset ID `102008118176022`.

## Files

- `upload/`: seven square 256×256 transparent PNGs for UI icons.
- `small/`: seven 128×128 transparent PNGs for smaller UI placements.
- `large/`: seven 512×512 transparent PNGs for larger popup illustrations or artwork uploads.
- `originals/`: full-resolution sources preserved separately from runtime assets.
- `index.html`: light/dark gallery with previews at 32, 64 and 96 pixels.
- `PremiumIllustrations_Ready.zip`: optimized variants, gallery, prompts and validation. Originals remain in the project and are excluded from the ZIP.
- `prompts.json`: exact generation prompts, source paths and reuse attribution.
- `integration_map.json`: planned consumer paths and existing Smart Pump ID.

Use 256px for Store icons and 512px for a larger Offline Earnings illustration. Keep titles, prices, multipliers and earned amounts as UI text so they stay dynamic and localized. The mint plus sign on Extra Cargo Slot indicates carrying capacity; coin artwork deliberately contains no Robux symbol.

Update 14/10/2026: six new images have been uploaded through Studio MCP and connected in the source UI. `roblox_asset_ids.json` contains the IDs. Store uses the four new gamepass illustrations plus the existing Smart Pump, its Wind Storm banner uses the new wind image, and Welcome uses Offline Earnings at 128px. The user granted TestGame access and restarted Studio. All nine images in the combined UI/scenery integration returned Success. The real-client test verified all five gamepass images, wind, offline and both scene images; Fit, untinted colors and loading checks passed. Offline artwork and the Collect button fit a Samsung Galaxy A06 landscape preview. Rojo sync, Selene, Luau type checks and build passed. Evidence is in `studio_validation.json`. Play and device simulation were stopped. This task does not add Inferno Dragon to gameplay.

## Connection check

Both Roblox MCP servers connected to TestGame, place `95006900120444`, in Edit mode. The official MCP read the current five gamepass definitions and confirmed they match local Config. Blender MCP could not connect to its addon; raster generation did not need Blender. Details are in `mcp_connection_check.json`.

## Validation

The export script checks square RGBA sources with transparent pixels, verifies each exported PNG, and records dimensions and file sizes in `validation.json`. Original generation alpha is retained; resizing uses LANCZOS. Artwork was visually reviewed as a set at full and reduced sizes. These are file/art checks; the new images have not yet been tested for Roblox asset loading.

Rebuild optimized exports and ZIP: `python tools/icons/export_premium_art.py`.
