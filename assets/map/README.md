# Map backups

- `Lobby.rbxm` — `Workspace.Lobby` (art-deco hotel lobby, ~960 anchored parts, no scripts)
- `Assets.rbxm` — `ServerStorage.Assets` (contains `ElevatorCab`)
- `LightingEffects.rbxm` — `Lighting` children: Atmosphere, Bloom, ColorCorrection, Sky ("Milky Sky", Creator Store 140015879511661)

Restore: right-click the parent in Explorer → Insert from File, or the robloxstudio MCP `import_rbxm`.

## Look: "Midnight Deco"

Warm-white cove light and bronze trim carry the architecture; neon colour is reserved for
things the player acts on (cyan = Normal elevator, magenta = Daily elevator, gold = money boards,
station accents). Dark polished marble floor so light pools read. Key lights live in
`Workspace.Lobby.Lights.KeyLights` (elevator hero spots, pillar uplights, skylight moonbeam).
In runs, `src/client/Controllers/Ambience.luau` layers a per-theme colour grade on top.

Lighting service properties are not inside the rbxm files; re-apply them by hand:

| Property | Value |
|---|---|
| LightingStyle | **Realistic** + PrioritizeLightingQuality on (current Studio replaced Technology with these; Soft flattens local lights) |
| ClockTime | 0 |
| Brightness | 2 |
| Ambient | 54, 48, 72 |
| OutdoorAmbient | 76, 76, 108 |
| ExposureCompensation | 0.25 |
| EnvironmentDiffuseScale / SpecularScale | 0.6 / 1 |
| Bloom | Intensity 0.7, Size 30, Threshold 1.35 |
| ColorCorrection | Brightness 0.02, Contrast 0.12, Saturation 0.04, Tint 255,246,236 |
| Atmosphere | Density 0.22, Haze 0.55, Color 86,76,116, Decay 44,38,70 |

Lobby shell (place edit, 2026-10-23 brighten pass): walls 64,54,80, marble floor 88,78,98, every lobby
light ×1.35 brightness. The first relight was too dark on real screens; keep shadows readable, not black.
