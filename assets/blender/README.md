# Blender props (art deco set)

Source: `props.blend` (Blender 5.2). Each prop is exported as FBX (Y-up, -Z forward, 1 unit = 1 stud):

| File | Size (studs) | Use |
|---|---|---|
| `DecoDial.fbx` | 9 × 5.6 × 0.6 | semicircular floor-indicator dial above elevator doors |
| `FlutedPillar.fbx` | 3.4 × 10 × 3.4 | fluted column (scale up for the lobby pillars) |
| `FanSconce.fbx` | 2.5 × 2.8 × 1.4 | wall sconce |
| `Sunburst.fbx` | 8.8 × 4.4 × 0.4 | sunburst ornament over doors / cab back wall |
| `DecoDesk.fbx` | 9.1 × 2.1 × 2.9 | stepped reception desk |
| `Topiary.fbx` | 2.4 × 6.4 × 2.4 | geometric topiary in an octagonal gold-trimmed planter |

`props_render.png` is a showcase render of the set.

The lobby currently uses Part-built equivalents of all these props, so nothing is missing in game.

### Uploaded mesh versions

`props_split/<Name>.fbx` are the same props split into one mesh per material, because a Roblox MeshPart holds only one material. Their parts are:

- `Dark`: Marble #100e16
- `Gold`: Metal #d4ac46
- `Neon`: Neon #00e1ff
- `NeonPink`: Neon #ff46af
- `Leaf`: LeafyGrass

They are uploaded as Model assets owned by **group 675923086**. User-owned uploads are not loadable in this group-owned place. Assembled copies live in `ServerStorage.__PropMeshes` (front = +Z, pivot at the centre), with a backup in `assets/map/PropMeshes.rbxm`.

| Prop | Asset id |
|---|---|
| FlutedPillar | 92897599001191 |
| Topiary | 122746123236429 |
| FanSconce | 123008714607717 |
| DecoDial | 134408634383720 |
| Sunburst | 98037135323916 |
| DecoDesk | 94802215801876 |
