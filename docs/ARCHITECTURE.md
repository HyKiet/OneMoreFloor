# One More Floor — Architecture & Contracts

Push-your-luck elevator game. Up to 8 players board an elevator; every floor is a ~20 s survival
challenge built from primitive parts. Survivors' bags compound; after each floor everyone chooses
**DEEPER** or **LEAVE** (bank the bag). Dying loses the bag. Dead players watch from a glass booth
above the arena and vote curses onto the next floor.

## Repo layout (Rojo)

| Path | Studio location | Owner |
|---|---|---|
| `src/shared/*` | `ReplicatedStorage.Shared` | core |
| `src/server/init.server.luau` | `ServerScriptService.Server` (Script) | core |
| `src/server/Services/*` | `ServerScriptService.Server.Services` | core |
| `src/server/Run/*` | `ServerScriptService.Server.Run` | core |
| `src/server/Challenges/*.luau` | `ServerScriptService.Server.Challenges` | challenges |
| `src/client/init.client.luau` + `src/client/Controllers/*` | `StarterPlayerScripts.Client` | client/UI |
| `Packages/` (Wally: Trove, Signal) | `ReplicatedStorage.Packages` | — |
| `ServerPackages/` (Wally: ProfileStore) | `ServerScriptService.ServerPackages` | — |

The **map** (lobby, lighting, cab asset) lives in the place file, not in Rojo. Rojo leaves unknown
Workspace / ServerStorage / Lighting children alone. Backups are exported to `assets/map/*.rbxm`.

`Workspace.StreamingEnabled = false` (set by Rojo) — clients see every arena.

## Shared modules
- `Config` — every tunable (timings, economy, themes, product ids).
- `Net` — remote registry; `Net.Event(name)`, `Net.Function(name)`. Full list + payloads in the file header.
- `Relics`, `Curses`, `Upgrades`, `Rarity` — data definitions.
- `Format` — `Format.Short(n)`, `Format.Cash(n)`, `Format.Comma(n)`.
- `Sounds` — name → `{ Id, Volume, Looped? }`; Id 0 = silent.

## Run lifecycle (server, `Run/Run.luau`)

```
Lobby boarding zone (countdown) ──► Descending (doors closed, arena built)
  ► Briefing (doors open, players teleported onto arena spawns, hazards idle)
  ► Challenge (template Start; eliminations live)
  ► Results (Judge, survivors' bags grow, relic rolls, survivors back into cab)
  ► Decision (DEEPER / LEAVE; spectators vote curses; run shop after boss floors)
  ► Descending … until nobody is left ► Ended
```

Eliminations: overlapping any part in `ctx.HazardFolder`, falling `Config.KillDepth` below the
arena origin, humanoid death, or `ctx:Eliminate`. Shields / Phoenix / banked Extra Lives can save you
(you are put back on a spawn with brief invulnerability).

Revive window (Normal mode): an eliminated player with a bag at stake gets an Extra Life offer for
`Config.Monetization.ReviveWindow` seconds (`You.ReviveUntil`). If everyone is out, the run waits in
"Results" (`Run:_awaitRevives`) until the offer closes, someone revives, or an open purchase prompt
(`Run:HoldRevive`) finishes. A revive restores the bag minus what insurance already banked.

Floor picking (`ChallengeRegistry.Pick`): every normal template belongs to a depth **zone**
(`Config.Zones`: zone 1 = B1-B9, zone 2 = B10-B19, zone 3 = B20+). A run picks an unseen floor from the
current zone, else an unseen one from the nearest zone, so **nothing repeats until the run has played every
eligible floor** (`Run.Seen`); after that it replays this zone and shallower ones, skipping the last 6.
Boss floors (every 5th) always pick a `BossOnly` template when one is eligible (The Cube from floor 5,
The Eye from floor 10): unseen first, then one not played recently, so bosses alternate.

Studio-only test switches (ignored in live servers):
| Where | Attribute | Effect |
|---|---|---|
| workspace (playtest server) | `OMF_ForceChallenge = "<Id>"` | force a template on every floor |
| workspace (playtest server) | `OMF_StartFloor = 21` | runs start on that floor |
| workspace (playtest server) | `OMF_NoCurses = true` | no random curses |
| player (server) | `OMF_God = true` | survive everything; `OMF_GodSaves` counts would-be deaths |
| workspace (**edit mode**, before Play) | `OMF_MockData = true` | throwaway ProfileStore profiles: test runs never touch real saves |

### `RunUpdate` payload (server → each run member; `nil` = not in a run)
```lua
{
  RunId = "string", Mode = "Normal" | "Daily",
  Phase = "Descending" | "Briefing" | "Challenge" | "Results" | "Decision" | "Ended",
  Floor = 7, IsBoss = false,
  EndsAt = 12345.6,            -- compare with workspace:GetServerTimeNow()
  Challenge = { Id, Name, Hint } | nil,
  Curses = { "Darkness", ... }, -- active on this / the upcoming floor
  Multiplier = 1.27,           -- your bag growth if you survive the next floor
  ShopOpen = false,            -- run shop available during this Decision
  Alive = 5, Total = 8,
  You = {
    Status = "Alive" | "Dead" | "Left",
    Bag = 1234, Shields = 1, Choice = "Deeper" | "Leave" | nil,
    Insured = false, CharmFloors = 0, Bought = { Shield = true },
    LastGain = 230,            -- bag gained on the last floor (Results phase)
    ReviveUntil = 0,           -- server time the Extra Life offer closes (0 = none)
    ReviveBag = 0,             -- bag a revive would restore
    ExtraLifeUsed = false,     -- the once-per-run revive is spent
  },
  Players = { { UserId, Name, Status, Bag, Choice } , ... },
}
```

### `Data` payload (server → owner)
```lua
{
  Cash, LifetimeCash, DeepestFloor, TotalRuns,
  Upgrades = { Insurance = 2, ... }, Relics = { Sneakers = 1, ... },
  Equipped = { "Sneakers" }, Slots = 1,
  Daily = { Streak = 3, CanClaim = true, NextReward = 250 },
  DailyBest = 12,              -- best Daily Elevator floor today
  Passes = { DoubleCash, VIP, LuckyBellhop, StarterPack },  -- booleans
  Stats = { FloorsCleared, Deaths, CashOuts, BiggestCashOut },
  FirstTime = true,            -- has never finished a run
  ExtraLives = 0,              -- banked Extra Lives (auto-save in Normal runs)
  Premium = false,             -- Roblox Premium (+10% cash-outs)
  PaidRandomAllowed = true,    -- PolicyService: Relic Capsule allowed for this player
  CapsuleCost = 1000, CapsuleFloor = 5,   -- capsule price; odds = Rarity.Odds(CapsuleFloor)
  CashPacks = { CashSmall, CashMedium, CashLarge },         -- cash each pack grants right now
}
```

Monetization contract (products, passes, remotes `PromptProduct` / `PromptPremium` / `PolishRelic` /
`BuyCapsule`, `Eliminated` fields `ReviveUntil, ReviveBag, ExtraLifeKey`): see `docs/MONETIZATION.md`
and `src/server/Services/MonetizationService.luau`. Receipts follow ProfileStore's developer-product
pattern: the receipt id is stored in `Data.Purchases` (last 100) together with the grant, and
`PurchaseGranted` is returned only once a DataStore save contains it (`DataService.WaitForReceiptSaved`).
Any Extra Life key a client sends is re-priced by the server for the player's depth. Golden Hour lives in workspace attributes
`OMF_GoldenUntil` (server time) and `OMF_GoldenBy` (buyer name). Player attribute `VIP` drives the chat tag.

### `Effect(name, args)` (server → client)
| name | args | client does |
|---|---|---|
| `Shake` | `{ Intensity, Duration }` | camera shake |
| `Flash` | `{ Color, Duration }` | full-screen colour flash |
| `Descend` | `{ Duration, Floor }` | elevator descent: rumble, light flicker, hum, floor counter roll |
| `CoinPop` | `{ Position, Amount }` | floating "+$12" at a world position |
| `Curses` | `{ List = { ids } }` | apply client curses (Darkness, Fog, Shaky); empty list clears |
| `Sound` | `{ Name }` | play a `Sounds` entry |
| `Banner` | `{ Text, Color }` | big centre text for ~1.5 s (from `ctx:Announce`) |
| `Confetti` | `{}` | celebration burst (cash out, rare relic) |

Player attributes set by the server: `InRun` (bool), `DoubleJump` (bool — client implements the
double jump), `RunStatus` ("Alive"/"Dead"/"Left"/nil).

## Challenge templates (`src/server/Challenges/<Id>.luau`)

```lua
return {
  Id = "LayerDrop",              -- must equal the file name
  Name = "Layer Drop",           -- shown huge during Briefing
  Hint = "Tiles vanish after you touch them. Drop through three layers!",
  MinFloor = 1,                  -- first floor it can appear on (zones do the depth gating; keep 1)
  MinPlayers = 1,                -- needs this many alive players
  Weight = 1,                    -- relative pick weight
  BossOnly = false,              -- true = only on boss floors (every 5th)
  Zone = 1,                      -- 1 = B1-B9, 2 = B10-B19, 3 = B20+ (see Config.Zones)
  Duration = 20,                 -- seconds, or function(ctx) -> number
  Build = function(ctx) end,     -- build geometry (doors are closed); optionally ctx:SetSpawns
  Start = function(ctx) end,     -- start hazards; runs in its own thread, may yield
  Judge = function(ctx) end,     -- optional: when time is up, eliminate players who failed
}
```

Arena conventions: `ctx.Origin` is the arena centre **on the floor surface** (floor top at local
y = 0), local −Z points away from the cab. Keep geometry within ±`Config.ArenaHalfExtent` (60) on
X/Z and below +60 on Y (the spectator booth sits at +80). Use `ctx.Theme` colours
(`Floor`, `Primary`, `Secondary`, `Hazard`) so arenas recolour as players go deeper. Scale danger
with `ctx.Difficulty` (≈0 on floor 1, ≈1 on floor 26, boss +0.2, `Hyper` curse +0.3). Every floor must
scale smoothly over 0 → 1.25: once a run has seen everything, all floors come back at zone-3 difficulty.
Zone-1 floors must be very easy at B1-B3 (tutorial). Spawns default to a ring of radius 12 at y = 3.
Players can move during the Briefing countdown: a floor where a head start matters holds everyone behind a
collidable ForceField gate (`CastShadow = false`) built in `Build` and dropped at the top of `Start`
(GlassBridge, RedLight). Players zoom out at most `Config.CameraMaxZoom` (30) studs, so a maze or memory floor
cannot be read from high above.

`ctx` API (see `src/server/Run/Context.luau`): `At, Part, Hazard, MakeHazard, Decor, Warn, Fx, Impact,
Animate, Rim, RoundRim, Glow, Trail, Emitter, Tween, After, Every, Wait, Heartbeat, Elapsed, Remaining,
Finish, GetAlive, GetCharacter, GetRoot, GetHumanoid, LocalPosition, FeetY, Eliminate, SetSpawns, Teleport,
Knockback (client-applied shove), SetPush (continuous force, e.g. wind), Sign / Billboard (text),
Prop (optional art from `ServerStorage.Assets.Props`, primitives as fallback), SpawnCoin, Announce, Shake,
Sound`, fields `Floor, IsBoss, Difficulty, Mode, Origin, Folder,
HazardFolder, Trove, Rng, Theme, Curses, Ended, State`. Client animation tags (ArenaFx): `OMF_Spin`,
`OMF_Pulse`, `OMF_Slide`, `OMF_Orbit` (+ `OrbitAxis`), `OMF_Swing` (pendulum).

**No z-fighting:** never let two visible faces share a plane. Thin floor decor layers sit ≥ 0.04 studs
apart; a disc under a floor must have its top face below the floor top (see `Context:RoundRim`).

**No neon glare:** neon emits above the bloom threshold, so big bright neon faces flood the screen.
`ctx:Part` caps the colour value of opaque neon parts whose largest face exceeds 24 studs² (harder the
bigger, down to 0.5 at 400 studs²) and keeps doing so when the part is recoloured or faded in later
(`Context.TameNeon`, opt out with `NeonGuard = false`). Design for it anyway: neon for thin trims, small
lights and small hazards; big surfaces in SmoothPlastic / Glass / Metal / ForceField with a neon edge.
Grids of many neon tiles add up even when each tile is under the cap: run them at value ~0.45 (Colour
Memory: yellow 0.56 and orange 0.55 with shifted hues so they stay distinct). Neon reads as fully lit down
to about value 0.45 and goes flat below ~0.35. Coins are neon at (190, 140, 25) for the same reason.
Long trims that run round a whole arena (rims, kerb lights, wall-top trims in a maze) add up too: keep them
at 0.5-0.65, and yellow / white accents at ~0.6 (they have the highest luminance). `Context:Rim`'s default
line is the theme Primary capped at 0.8; the shaft bands (`Run:_tintLights`) are capped at 0.6. No theme
accent is pure white (The Void's Primary is (200, 204, 226), Gold Vault's Secondary (236, 230, 214)).

**Lighting moods ("Midnight Deco", client `Ambience`):** the place's Lighting service holds the lobby mood (warm
lounge, dim moon: Brightness 1.2; values in `assets/map/README.md`). In a run Ambience switches to the **cab**
mood while you ride down (low ambient, the cab's warm panels light you) and the **arena** mood otherwise
(`RUN_LIGHT` / `VOID_LIGHT`: Brightness 2, lifted ambient; a per-theme colour grade; a thin theme-tinted
Atmosphere haze for depth). It writes `Ambient`, `OutdoorAmbient`, `Brightness`, `ExposureCompensation` and
the Atmosphere. The curses in `Effects` own those while they run: Darkness while `Lighting.OMF_Darkness`
exists, Fog while the Lighting attribute `OMF_FogCurse` is set; when a curse ends Ambience re-applies its
target. The descent effect (`Effects.cabRide`) hums the cab lights with one or two short brownouts (never a
strobe) and sweeps one local light up past the doors per passing floor, tinted by the destination theme.
Arena overhead lights (`Run:_buildArenaLights`): four coloured corner washes (the theme's two accents,
swapped every floor, hue drifting a little per floor via `floorHue`) and a near-white centre key that is
the only shadow caster.

**No dark maps:** arenas sit under the lobby's night sky (ClockTime 0). During a run the client's Ambience
lifts `Lighting.Ambient` / `OutdoorAmbient` (less on The Void) and theme `Floor` colours are mid tones
(HSV value ~0.4). Big walkable surfaces and big walls must read at a glance: do not lerp `Theme.Floor`
toward black by more than ~0.2 for big parts (small trims and housings may stay dark), walls should
contrast with the floor, and check a screenshot at a zone's first floor, at B31 (Gold Vault) and at B46
(The Void, the darkest theme; avoid floors divisible by 5 for screenshots, boss floors get a red grade). The
Darkness curse in client `Effects` saves/restores the same Lighting properties; Ambience only writes them
while its `OMF_Darkness` grade is absent.
- Floors that are dark on purpose (Spotlight) clamp a minimum HSV value (0.2) instead of a plain lerp, or
  The Void's floor goes pitch black. The Void's colour grade keeps contrast modest (0.12): more crushes
  dark floors to black.
- The moon (ClockTime 0) is the only directional light and it casts shadows: anything solid between a
  floor and the moon (behind / above it) can black the floor out, since shaded areas get only ambient.
  Translucent collidable parts (ForceField gates, glass) need `CastShadow = false` (`ctx:Decor` already
  does this). Glass Bridge's gate blacked out its start tower this way.
- The `Glass` material mirrors the black night sky and reads as a hole: use SmoothPlastic with
  Transparency ~0.3 and a pale tint for panes you stand on.

**Props** (`ServerStorage.Assets.Props`, place file; Blender sources in `assets/blender/arena/`): Models with
the pivot at the bottom centre and the front facing −Z. `Car` (4.1×3.1×7.7), `TrainEngine` (4.3×5.1×13.8),
`TrainCar` (4.3×5.0×11.6), `Ghost` (3.8×4.4×3.8), `Dome` (6.4×6.1×6.4). Parts are named by role (`Body`,
`Nose`, `Glass`, `Dark`, `Metal`, `Gold`, `NeonHead`, `NeonTail`, `Eyes`) so templates can recolour `Body`.

## Map contract (place file)

```
Workspace.Lobby (Model)
  Spawn                      SpawnLocation (Neutral, Duration 0)
  Elevators.Normal           Model; child Part "BoardingZone" (invisible, CanCollide false,
                             Anchored, ~18x10x12) in front of the elevator doors
  Elevators.Daily            same, for the Daily Elevator
  Stations.Upgrades|Relics|Daily   Model/Part each with a child BasePart "PromptPart"
  Boards.Deepest|Daily|Cash  BasePart; leaderboard SurfaceGui goes on its Front face

ServerStorage.Assets.ElevatorCab (Model)   cloned per run
  pivot (WorldPivot) = centre of the floor's TOP surface, LookVector = out through the door (-Z)
  interior ≈ 24 (X) × 14 (Y) × 20 (Z); door opening 10 wide × 10 high in the front wall
  DoorL, DoorR               BaseParts closing the opening; server slides them ±X 5.5 studs
  Display                    BasePart above the door inside; Front face points into the cab
  Spawns                     Folder with 8 invisible parts where players stand
  Lights (optional)          Folder of parts with lights the client flickers during Descend
```
The server falls back to procedural geometry when an anchor is missing, so the game always runs.
