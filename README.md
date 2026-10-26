# One More Floor

Push-your-luck elevator game for Roblox. Up to 8 players ride an elevator down; every floor is a
short survival challenge. Survive and your bag grows ×1.25 per floor — then choose **DEEPER** or
**LEAVE** (bank it). Die and the bag is gone. Dead players watch from a glass booth and vote curses
onto the survivors.

- Architecture & contracts: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Launch checklist: [docs/SETUP.md](docs/SETUP.md)

## Development

Tools: [Aftman](https://github.com/LPGhatguy/aftman) (Rojo 7.7.1, Wally 0.3.2).

```bash
aftman install
wally install          # Trove, Signal, ProfileStore
rojo serve             # then Connect from the Rojo plugin in Studio
```

Code lives in `src/` and is synced by Rojo. The map (lobby, elevator cab, lighting) lives in the
place file; backups are exported to `assets/map/`. Blender sources are in `assets/blender/`.

| Folder | What |
|---|---|
| `src/shared` | Config, remotes (Net), relics, curses, upgrades, sounds |
| `src/server/Services` | Data (ProfileStore), economy, lobby, elevators, leaderboards, monetization, analytics, badges |
| `src/server/Run` | Run state machine, challenge context, cab, modifiers, challenge registry |
| `src/server/Challenges` | One module per floor challenge |
| `src/client` | UI and client effects |

Tuning lives in `src/shared/Config.luau` (timings, economy curve, relic odds, themes, product ids).
