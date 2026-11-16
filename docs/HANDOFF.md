# One More Floor: Session handoff

Read this first in a new chat. Updated 2026-10-26 (see "2026-10-26 session" below). Deeper references: `docs/ARCHITECTURE.md`
(code contracts, template contract, **neon / dark-map rules**), `docs/MONETIZATION.md` (economy + Robux design),
`docs/SETUP.md` (launch checklist), `assets/map/README.md` (map + lighting values),
`docs/GAME_REVIEW_2026-10-25.vi.md` (full game review with a prioritised findings list),
`docs/ICON_THUMBNAIL_PLAN.vi.md` + `assets/marketing/v3/` (store icons / thumbnails, done in another session).

## 1. The project in one paragraph
Roblox push-your-luck elevator game. Up to 8 players ride down; each floor is a ~20-30 s survival
challenge; survivors' bag grows ×1.25 per floor (×1.5 on boss floors, every 5th); after each floor everyone
picks DEEPER or LEAVE (bank the bag). Dying loses the bag. Dead players spectate, vote curses, and can buy
Curse / Bless / Extra Life. Meta: 24 relics, upgrades, daily streak, Daily Elevator (shared seed),
leaderboards. Art: primitives + neon, plus a few Blender props (cars, train, ghost, dome); the owner allowed
Blender and the Creator Store for floor art in the 2026-10-24 brief. Replies to the owner in **Vietnamese**;
code, comments and in-game text in English.

## 2. Environment
- Place "Test", placeId 139070842708870, universe/GameId 10772257156, **group-owned** (group 675923086).
  Owner user id 11109892746 (Roblox name SHKDev2005).
- Rojo 7.7.1 `rojo serve` (port 34872) live-syncs `src/` → Studio. Wally packages: Fusion 0.3.0 (UI),
  Trove, Signal, ProfileStore (server).
- **Place file** holds the map, lighting, `ReplicatedStorage.RelicModels` and `ServerStorage.Assets.Props`
  (backups in `assets/map/`, Blender sources in `assets/blender/`). The owner must **Save/Publish** after
  place edits. Nothing in the place was edited on 2026-10-25 (code only).
- MCPs (`.mcp.json`): `robloxstudio` (@chrrxs; Studio plugin 3.4.0 matches; instance id changes after a Studio
  restart, get it with `get_connected_instances`), `Roblox_Studio` (official; `list_roblox_studios` for the
  id), `blender` (Blender 5.2.2, addon 1.8; asset libraries / generators are off). A log line "plugin v3.4.0
  does not match MCP server v3.1.6" comes from another session's stale npx server: harmless.
- Syntax check: `"$TEMP/luau-tool/luau-compile.exe" --null <files>`. The IDE's red diagnostics are false
  positives (non-Luau parser). Keep CRLF line endings (Git Bash `sed -i` turns files into mixed endings;
  edit with the Edit tool or Python that preserves `\r\n`).
- Open Cloud key: user env var `ROBLOX_OPEN_CLOUD_API_KEY`. Scopes: **assets read/write only** (no
  DataStore, no monetization). Never print it.
- Git: pushed to https://github.com/HyKiet/OneMoreFloor (branch `main`, first commit 2026-10-26); commit only
  when the owner asks.
- Screenshots (`capture_screenshot`) fail with "Unknown error" while another window covers Studio: bring Studio
  to the foreground first (PowerShell `SetForegroundWindow` on the RobloxStudioBeta main window).

## 3. Current state
### 3.1 Floors: 20 templates in 3 depth zones (`src/server/Challenges/`)
Every floor has its own core verb (the 2026-10-24 rebuild archived 10 look-alike floors to
`archive/challenges/`). `Config.Zones` / `Config.ZoneFor`: zone 1 = B1-B9 (difficulty ~0-0.32), zone 2 =
B10-B19 (~0.36-0.72), zone 3 = B20+ (~0.76-1.25). `ChallengeRegistry.Pick` takes an unseen floor from the
current zone, else the nearest zone; a run never repeats a floor until it has played them all (`Run.Seen`),
then every floor comes back at zone-3 difficulty. Boss floors (every 5th) always pick a boss.

| Zone | Id | Name | Core verb |
|---|---|---|---|
| 1 | RedLight | Red Light, Green Light | run on green, freeze on red; a Watcher zaps movers |
| 1 | HoleInWall | Hole in the Wall | energy walls sweep across; stand in the doorway |
| 1 | JumpRope | Jump Rope | giant neon rope swings round the deck; jump it, it speeds up |
| 1 | MemoryTiles | Colour Memory | a colour is called, other tiles vanish; deeper hides colours first |
| 1 | ShellGame | Shell Game | follow the gem under shuffling domes, stand on the right pad |
| 1 | PopQuiz | Pop Quiz | quick question on a big screen; stand on the right answer platform |
| 1 | RushHour | Rush Hour | Frogger: roads, railway, lava river with rafts (Blender cars / train) |
| 2 | VaultRun | Vault Run | grab cash (worth more far away), be back in the vault before it shuts |
| 2 | HotPotato | Hot Potato | pass the bomb by touch (2+ players only, MinFloor 2) |
| 2 | GlassBridge | Glass Bridge | memorise the flashed safe path, jump across glass rows |
| 2 | LayerDrop | Layer Drop | touched tiles drop; fall through 3 layers, don't fall off the last |
| 2 | WindTunnel | Wind Tunnel | fans blow you off the deck; walk into the wind, hide behind walls |
| 2 | HauntedMaze | Haunted Maze | find the exit while ghosts hunt you (Blender ghost) |
| 2 | SimonSays | Simon Says | obey only orders that start with "SIMON SAYS" |
| 3 | LavaRise | The Floor Is Lava | climb floating steps before the lava reaches you |
| 3 | Spotlight | Spotlight | stay inside roaming spotlights in the dark |
| 3 | NeonSnake | Neon Snake | eat orbs to grow a tail; touching any tail is out; eat your quota |
| 3 | PaintParty | Paint Party | paint tiles your colour; rollers wipe lanes; own your quota |
| boss | BossSlam | BOSS: The Cube | dodge slams, jump shockwaves (B5+) |
| boss | BossEye | BOSS: The Eye | hide behind crumbling pillars when it flashes (B10+) |

Props (`ServerStorage.Assets.Props`, via `ctx:Prop(name)` with primitive fallback): `Car`, `TrainEngine`,
`TrainCar`, `Ghost`, `Dome` (sizes/naming in ARCHITECTURE.md).

### 3.2 Visual state (2026-10-25)
- Neon glare and dark maps were the owner's two visual complaints. Both are fixed and the rules are in
  ARCHITECTURE.md ("No neon glare", "No dark maps"); follow them for any new floor.
- In-run lighting: `src/client/Controllers/Ambience.luau` lifts Ambient/OutdoorAmbient (`RUN_LIGHT`,
  `VOID_LIGHT`) and applies a per-theme colour grade; it respects the Darkness curse.
- Themes (`Config.Themes`): Lobby Blue B1, Ultraviolet B10, Inferno B20, Gold Vault B30, The Void B45. Floors
  are mid tones; no accent is pure white.
- Screenshot-verified this session (player view and overview): HauntedMaze B11/B31/B48, LayerDrop B12/B33,
  GlassBridge B13/B46, WindTunnel B16/B22, SimonSays B18, PopQuiz B2/B49, RushHour B4/B32, NeonSnake B21,
  PaintParty B23, Spotlight B47, RedLight B3, cab interior (descending). Earlier the same day: ShellGame,
  RedLight, HoleInWall, JumpRope, BossEye, VaultRun, LavaRise, Spotlight B30, MemoryTiles B6/B7/B30, BossSlam.

### 3.3 Monetization
- Product and pass ids are **set** in `Config.Products` / `Config.Passes` (9 products incl. 3 Extra Life
  tiers, 4 passes). `Config.Badges` ids are still **0**. Store/UI images: `src/shared/Images.luau` (v3 icons,
  another session).
- **Pass-ownership fix (task 1, 2026-10-24):** `DataService` keeps `OwnedPasses` in the profile;
  `MonetizationService.checkPass` turns a pass on at once if a previous session confirmed it, then asks
  Roblox with retries `{2, 5, 10, 20, 40, 60}` s, and only drops it on a confirmed "not owned". So a web
  error at join no longer locks a paying player out for the session. Runtime check: OwnedPasses fills for
  all four passes with no errors (the failure path itself cannot be simulated in Studio).

### 3.4 2026-10-26 session (all screenshot / runtime verified in Studio)
- **Real-money fixes:** receipts confirmed only after a durable save (`DataService.WaitForReceiptSaved`);
  `ExtraLife2/3` aliases re-priced by depth; banked Extra Lives only spent when the bag > $0; VIP and Extra
  Life shop text now match the code (VIP: "x1.275 per floor instead of x1.25").
- **Shop on phones:** `Panels` pages can set `PhoneLayout` (Shop does): portrait = full-screen modal laid out
  430 wide and zoomed (one product per row), landscape phones = x1.2 zoom with the tabs on the title row;
  the code box moves into the scroll list on phones. Other tabs keep the old modal.
- **Camera:** `Config.CameraMaxZoom = 30` (client `Movement`), StarterPlayer matches.
- **Red Light:** a ForceField start gate holds players through the Briefing countdown and drops on GO;
  anyone past the line at GO is put back on a spawn.
- **Lighting relit ("Midnight Deco"):** lobby lounge (place), low-key cab + cabRide flicker, arena moods,
  per-floor arena light colours, only the centre arena light casts shadows. Values in `assets/map/README.md`,
  code contract in ARCHITECTURE.md "Lighting moods". Curses verified after the change (Darkness + Fog on B2,
  restore on B3).

## 4. Studio testing (how the floors were tested)
- Studio-only switches (all gated by `RunService:IsStudio()`):
  - workspace `OMF_ForceChallenge = "<Id>"` (forces the template on every floor, boss floors too),
    `OMF_StartFloor = n`, `OMF_NoCurses = true`: set them **in the playtest server**, not in edit mode.
  - workspace `OMF_MockData = true` is set **in edit mode right now**: every Studio tester plays on a
    throwaway profile (protects the owner's real save from deep-floor test runs).
  - player attribute `OMF_God = true`: survives everything (`OMF_GodSaves` counts saves; shows a toast).
- One playtest at a time. Agents use a lock dir: `mkdir <scratchpad>/studio-playtest.lock` + an `owner` file,
  `rm -rf` it after `solo_playtest stop`. Kill orphaned background waiters from dead agents (PowerShell:
  `Win32_Process` whose CommandLine matches `studio-playtest`) before trusting the lock.
- Code changes only reach a playtest after a restart (the running server keeps the modules it loaded).
- Handy flow: start a playtest, then in `eval_server_runtime` set the switches, `plr:SetAttribute("OMF_God",
  true)`, `plr.Character:PivotTo(workspace.Lobby.Elevators.Normal.BoardingZone.CFrame)`; drive phases with
  `ElevatorService.GetRun(plr)` (`run.Phase`, `run.Floor`, `run.Ctx`, `run:Choose(plr, "Deeper"/"Leave")`).
  A server-side `task.spawn` "autopilot" that picks the next forced template at each Decision avoids
  missed decisions. For overviews, publish `run.Ctx.Origin` as a workspace attribute and set the client
  camera to Scriptable from `eval_client_runtime`. Timeline: 10 s countdown, 4 s descent, 3.5 s briefing.
- Tool gotchas: `eval_*_runtime` fails with "Unknown error" past ~40 s (keep waits short; check state after);
  it returns only the first return value. `execute_luau` says "Unknown error" when the code reads
  restricted properties (`Lighting.Technology`, DataStore version metadata). After a run ends the character
  respawns in the lobby a few seconds later: wait before pivoting to the boarding zone.
- Bots for playtesting floors live in the session scratchpad (gone in a new session); the PaintParty one
  follows lanes, dodges telegraphed rollers and reports `count / quota`.

## 5. Open items (priority order)
1. **Owner's real save (needs the owner's OK):** test runs on 2026-10-24 (before `OMF_MockData` existed)
   polluted the owner's profile (`OneMoreFloor_PlayerData_v1`, key `Player_11109892746`: cash 85,639, deepest
   32, 9 relics). Version **v3** of the key is the clean baseline (cash 56, deepest 17, runs 17, 4 relics,
   StarterGranted false; the Starter Pack is granted again on the next real join because the owner owns the
   pass). Restore plan: UpdateAsync keeping MetaData/UserIds, `Data = v3.Data`, keep the current Purchases
   list, abort if a session is active (or ProfileStore `VersionQuery` + `profile:SetAsync()`). Writing the
   DataStore is a shared-resource change: **ask first** (the owner answers "khôi phục save"). Afterwards
   remove workspace `OMF_MockData` in edit mode and remind the owner to Save the place.
2. Owner: Save the place (Ctrl+S) / publish so props, map and lighting edits from 2026-10-24 and the
   2026-10-26 relight (Lighting, Lobby lights, spawn, ElevatorCab, StarterPlayer zoom) are kept. Also update the
   VIP pass description on the Creator Dashboard to match the shop ("x1.275 per floor instead of x1.25").
3. Gameplay tuning still worth a human pass (bots and screenshots only so far): PaintParty quota at d ≥ 1.2
   (retuned 2026-10-25, see the comment in `plan`), NeonSnake quota, WindTunnel push strength, GlassBridge
   at 4+ lanes, HotPotato needs a 2-4 client multiplayer test (never playtested with real players).
4. GAME_REVIEW findings not yet done (see that doc): meta caps, badges (ids 0), Daily loadout fairness.
   (VIP text, Extra Life rules, receipt save, ExtraLife2/3 alias: done 2026-10-26.)
5. 8 players: characters collide with each other (no collision group), so crowded floors (GlassBridge panels,
   ShellGame pads, Spotlight discs late in the round, BossEye cover, JumpRope deck) allow body-blocking and
   shoves. Owner decision pending: a "Players" collision group that doesn't collide with itself.
6. Roadmap from MONETIZATION.md: Floor Pass, cosmetics, Express Ticket, Renovation prestige, Bellhop Club.

## 6. Gotchas
- Bright warm neon renders lemon-yellow under this lighting; use warm-white / dim bronze for trim.
- `require` from MCP Luau in edit mode runs a separate module copy; use `eval_server_runtime` in a playtest
  to reach live service state.
- Fast or round hazards need explicit swept checks in the template (the 0.1 s overlap monitor misses them);
  templates judge positions one round trip late for latency fairness (see JumpRope, HoleInWall).
- Studio screenshots from `capture_screenshot` are already in viewport pixels (no DPI division needed).
- Boss floors tint the screen red (Ambience boss grade): judge colours on non-boss floors.
