# AltairEdited Starter

Ready-to-use Roblox game foundation. **Clone this repository and build your game here.**
Do not fork upstream Altair again and do not treat this repo as a temporary migration branch.

This starter combines:

- Altair runtime topology (`ReplicatedStorage.client` + `client/exec`, preload, Reflex, Cmdr);
- production bootstrap hardening (controller readiness barrier, lifecycle logging, ProfileStore);
- built-in base/plot assignment for defense-style games;
- dual networking: `BridgeNet2` for UI and low-volume flows, `ByteNetMax` for high-throughput gameplay such as enemy units and zombie waves.

## Quick Start

1. Clone the repository and open it locally.
2. Run `bash init.sh`, then `bash update.sh`.
3. Change project identity before feature work:
   - `default.project.json` → `"name"`
   - `wally.toml` → `[package].name`
   - `src/shared/config/GameConfig.luau` → datastore key and game constants
4. Run `bash serve.sh` and connect from Roblox Studio with the Rojo plugin.
5. Build gameplay in this repo using the foundation boundaries below.

See [docs/README_GETTING_STARTED.md](docs/README_GETTING_STARTED.md) for the full new-game workflow.

## What Is Already Included

| Area | Included by default |
| --- | --- |
| Client runtime | `src/client` in `ReplicatedStorage.client`, entrypoint in `src/client/exec` |
| Preload | Loading screen, CoreGui lock, player data wait, `PlayerReady` |
| Server bootstrap | Readiness barrier, priority controllers, timeouts, progress logs |
| Data | `ProfileStore`, Reflex producers, `ServerData` session boundary |
| Monetization | Thin `ServerMonetization` + `MonetizationExecs` registry |
| Base / plot | `ServerBaseController` + `server/classes/Base.luau` |
| Collisions | `PlayerCollisions` with feature-flag style setup |
| Networking policy | Bridge for UI/lifecycle; ByteNetMax reserved for unit/wave replication |
| Tooling | Rokit, Wally, Rojo 7.6.1, scaffold, sourcemap scripts, TestService hook |

## Where To Add Your Game

| You are building… | Put it here |
| --- | --- |
| Wave / unit packets (ByteNetMax) | `src/shared/contracts/` |
| Wave / combat services | `src/server/modules/` or `src/server/services/` |
| Client wave presentation | `src/client/modules/` |
| Screens (HUD, wave UI) | `src/client/ui/` |
| Domain constants | `src/shared/config/` |
| Reflex slices | `src/shared/reflex/` |
| Server-only authority | `src/server/` — never in `shared/classes` |

## Foundation You Can Disable

If your game does not use player bases/plots, disable `ServerBaseController` in
`src/server/serverConfig/ServerInitConfig.luau`.

If you remove base world assets from the place, follow
[docs/README_BASE_FOUNDATION.md](docs/README_BASE_FOUNDATION.md).

## Documentation

- [Getting started](docs/README_GETTING_STARTED.md) — new game workflow in this repo
- [Base foundation](docs/README_BASE_FOUNDATION.md) — plot assignment and Studio requirements
- [Porting guidelines](docs/README_PORTING_GUIDELINES.md) — only when importing old systems
- [Altair migration notes](docs/README_ALTAIR_MIGRATION.md) — historical reference, not the primary onboarding path
- [Data handling](docs/README_DATA_HANDLING.md)
- [Networking](docs/README_SIGNALS_AND_BRIDGES.md)
- [Preload](docs/README_PRELOAD.md)

## Lineage

This starter descends from Altair `3.0.2` and selected CoreScripts production patterns.
That history is documented for maintainers; new projects should start from this repository directly.
