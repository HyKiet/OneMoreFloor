# Launch checklist

## 1. Studio settings (once)
- **Game Settings → Security → Enable Studio Access to API Services** — without it ProfileStore
  runs in mock mode (nothing saves in Studio) and leaderboards only show players in the server.
- **File → Publish to Roblox** after map changes. Code changes arrive through Rojo, but the place
  still has to be published for live servers to get them.

## 2. Monetization (Creator Dashboard → your experience → Monetization)
Create these (icons in `assets/icons/`), then paste the ids into `src/shared/Config.luau`. With the
robloxstudio MCP connected, Claude can create them via `manage_monetization`.

| Config key | Type | Price | What it does |
|---|---|---|---|
| `Products.ExtraLife` | Developer Product | 9 R$ | Extra Life, floors 1–9 (revive with your bag / banked save) |
| `Products.ExtraLife2` | Developer Product | 19 R$ | Extra Life, floors 10–19 |
| `Products.ExtraLife3` | Developer Product | 29 R$ | Extra Life, floors 20+ |
| `Products.CurseElevator` | Developer Product | 25 R$ | Spectator: random curse on the survivors' next floor |
| `Products.BlessElevator` | Developer Product | 25 R$ | Spectator: every survivor gets a Bubble Shield |
| `Products.GoldenElevator` | Developer Product | 39 R$ | Whole server: ×2 cash-outs for 15 min |
| `Products.CashSmall` | Developer Product | 49 R$ | 1× a typical bag at your deepest floor (min $1,500) |
| `Products.CashMedium` | Developer Product | 149 R$ | 3.6× (min $6,000) |
| `Products.CashLarge` | Developer Product | 399 R$ | 12× (min $25,000) |
| `Passes.StarterPack` | Game Pass | 99 R$ | $5,000 + 3 Extra Lives + a Rare relic (once) |
| `Passes.VIP` | Game Pass | 149 R$ | +1 relic slot, +10% bag growth, [VIP] chat tag |
| `Passes.LuckyBellhop` | Game Pass | 199 R$ | +25% relic chance, Relic Capsules 20% cheaper |
| `Passes.DoubleCash` | Game Pass | 249 R$ | ×2 cash when you leave with your bag |

Ids left at `0` show "Coming soon" instead of a purchase prompt. Relic Capsule odds are always shown
and the capsule is disabled where `PolicyService` restricts paid random items.

## 3. Badges
Create badges and paste ids into `Config.Badges` (`Welcome`, `FirstCashOut`, `Floor10`,
`Floor25`, `Floor50`, `LegendaryRelic`).

## 4. Analytics (Creator Dashboard → Analytics)
- Onboarding funnel: Joined → Boarded → Floor1 → Floor3 → FirstCashOut → FirstUpgrade.
- Custom events: `FloorCleared` (value = floor), `Eliminated` (field = challenge id),
  `CashOut` (value = amount), `UpgradeBought`, `ProductBought`, `PassBought`, `RelicPolished`,
  `CapsuleOpened`.
Use these to find the challenge that kills the most players on early floors and tune it.

## 5. Before publishing
- Playtest with 2–4 players (Test → Clients and Servers) and run at least to floor 6 (curses) and
  floor 5 (boss + run shop).
- Check mobile in the Device Emulator (UI scale, buttons reachable).
- Set the experience icon/thumbnail and a description that sells the hook:
  "Every floor doubles the risk. Go deeper or walk away?"
- Weekly updates: new challenge template (one file in `src/server/Challenges`) + a new curse or relic.
