# Arena props (Blender → Roblox)

Source: `arena_props.blend` (scene `ArenaProps`, Blender 5.2). Each prop is one FBX (Y-up, −Z forward,
1 unit = 1 stud) with one mesh per material, uploaded as a Model owned by **group 675923086**.
Assembled copies live in the place at `ServerStorage.Assets.Props.<Name>`: pivot at the bottom centre,
front facing −Z, parts renamed by role (`Body`, `Nose`, `Glass`, `Dark`, `Metal`, `Gold`, `NeonHead`,
`NeonTail`, `Eyes`). Templates get a copy with `ctx:Prop(name)` and keep a primitive fallback.

| Prop | Size (studs, X×Y×Z) | Used by | Asset id |
|---|---|---|---|
| Car | 4.1 × 3.1 × 7.7 | Rush Hour | 112609312269489 |
| TrainEngine | 4.3 × 5.1 × 13.8 | Rush Hour | 128971932787936 |
| TrainCar | 4.3 × 5.0 × 11.6 | Rush Hour | 124562908745097 |
| Ghost | 3.8 × 4.4 × 3.8 | Haunted Maze | 140132510318435 |
| Dome | 6.4 × 6.1 × 6.4 | Shell Game | 110786757272731 |
