# Relic models

Source: `relics.blend` (Blender 5.2). It was generated from the scripts `relickit.py` + `relics_build.py`, which are not kept in the repo; edit the .blend directly.
Each relic is a collection `R_<RelicId>`. It holds separate mesh objects, and each object becomes its own MeshPart in Studio:

| Part | Studio material |
|---|---|
| `Body` | main material (SmoothPlastic / Metal) |
| `Trim` | secondary (gold / metal / sole / rim) |
| `Neon`, `NeonRing` | Neon accents |
| `Glass` | Glass with transparency |
| `Eyes`, `Liner`, `Velvet` | small detail colours |

`parts.json` lists the colour, material and transparency for every part. The Studio assembly reads it.
`relics_sheet.png` is a contact sheet of the set.

## Export / upload

- One FBX per relic: `<RelicId>.fbx`. Export settings: Y-up, -Z forward, 1 unit = 1 stud. Each relic is about 3 studs across, centred.
- The FBX files are uploaded as **Model** assets owned by the **group 675923086**, because the experience is group-owned:
  - a user-owned upload loads with "User is not authorized" in this place;
  - `asset_ids.json` holds the asset id of every relic.
- The Roblox importer keeps the Blender axes. The assembly step rotates every model so that up is +Y and the front faces +Z, which is the direction the viewport camera looks from.
- In Studio the models live in `ReplicatedStorage.RelicModels.<RelicId>`:
  - each part is Anchored, with CanCollide, CanTouch, CanQuery and CastShadow off;
  - the pivot is at the centre.
- Backup: `assets/relics/RelicModels.rbxm`.

## Code

`src/client/Util/RelicModel.luau`:

- `RelicModel.mountRelic(viewport, relic, silhouette)` mounts the authored model, and falls back to the primitive builder if the model is missing.
- `RelicModel.clone(relic)` returns a copy for in-world use.
