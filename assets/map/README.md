# Map backups

- `Lobby.rbxm` — `Workspace.Lobby` (art-deco hotel lobby, ~960 anchored parts, no scripts)
- `Assets.rbxm` — `ServerStorage.Assets.ElevatorCab` (insert it into `ServerStorage.Assets`)
- `LightingEffects.rbxm` — `Lighting` children: Atmosphere, Bloom, ColorCorrection, Sky ("Milky Sky", Creator Store 140015879511661)

Restore: right-click the parent in Explorer → Insert from File, or the robloxstudio MCP `import_rbxm`.

## Look: "Midnight Deco" (cinematic moody neon, relit 2026-10-26)

**Lobby: a warm lounge.** Golden pools under the ceiling downlights and chandeliers, dimmer surroundings,
neon colour reserved for things the player acts on (cyan = Normal elevator, magenta = Daily elevator, gold =
money boards, station accents). Dark polished marble floor so the pools read. Key lights live in
`Workspace.Lobby.Lights.KeyLights` (elevator hero spots, pillar uplights, skylight moonbeam).

- Downlights: SpotLight Angle 56, Range 46, colour 255,198,134, Brightness 4 (2.2 for the two by the elevator
  keys, 3 for the one by the back wall over the spawn). Chandeliers 3.2, colour 255,202,138; only
  `ChandelierMain` casts shadows. Sconces 1.3 (255,186,116), pillar uplights 3.2, wall washes 3.4,
  moonbeam 2.0, MoonLight 1.2 (no shadows), elevator keys 5.4.
- Big warm-white neon (`SkyFrame` cove, pillar `Ring`s) is dim bronze 118,94,70: brighter warm neon renders
  lemon-yellow / orange under this grade.
- Spawn moved 6 studs toward the elevators (z = 34): at z = 40 the default camera was pressed into the back
  wall's gold `WainscotTrim`.

**Elevator cab (`ServerStorage.Assets.ElevatorCab`): low-key.** `LightPanel1` is the shadow-casting key
(2.6), `LightPanel2` a fill (1.7), `CabFill` 0.7, `AccentGlow` 0.9; panel neon 150,128,100. The `Mirror`
panels are smoked bronze SmoothPlastic (74,56,48, Reflectance 0.08): the Glass material mirrored the black
night sky and read as holes. The ride itself (hum, brownouts, passing-floor light) is client code in
`Effects.luau`.

**Runs** (`src/client/Controllers/Ambience.luau`): the cab mood while riding down, then the arena mood
(night sky lifted, per-theme grade and haze). Arena lights and shaft colours: `Run:_tintLights`.

Lighting service properties are not inside the rbxm files; re-apply them by hand (Ambience reads the lobby
values from here at startup, so these are the lobby mood):

| Property | Value |
|---|---|
| LightingStyle | **Realistic** + PrioritizeLightingQuality on (current Studio replaced Technology with these; Soft flattens local lights) |
| ClockTime | 0 |
| Brightness | 1.2 (arenas get 2 from Ambience) |
| Ambient | 44, 38, 58 |
| OutdoorAmbient | 62, 58, 86 |
| ExposureCompensation | 0.3 |
| EnvironmentDiffuseScale / SpecularScale | 0.5 / 0.8 |
| ShadowSoftness | 0.45 |
| Bloom | Intensity 0.55, Size 26, Threshold 1.45 |
| ColorCorrection | Brightness 0, Contrast 0.15, Saturation 0.02, Tint 255,243,232 |
| Atmosphere | Density 0.26, Haze 0.9, Color 96,76,110, Decay 58,40,66, Glare 0, Offset 0 |

StarterPlayer: CameraMaxZoomDistance 30 (matches `Config.CameraMaxZoom`).

History: the 2026-10-23 brighten pass (walls 64,54,80, marble floor 88,78,98, lights ×1.35) fixed a relight
that was too dark on real screens; keep shadows readable, not black.
