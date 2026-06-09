# AltairEdited Core Migration

This branch is based on the Altair `3.0.2` lineage. The exact baseline commit is
`39349d18f1afc01b84b7e7f4cbb6dde6ef0ad982` (`2026-05-31`,
`Merge pull request #1 from kardavx/macos-support`), which is after commit
`88637da` (`Update to Altair 3.0.2`).

Current changes from that Altair base:

- data persistence was migrated from `ProfileService` to `ProfileStore`;
- server bootstrap now waits for controller `Init`/`Start` completion before dispatching player lifecycle callbacks;
- server bootstrap logs controller lifecycle progress, timeouts, and summaries;
- Altair client runtime topology is kept: `src/client` is mounted in `ReplicatedStorage.client`, while `src/client/exec` remains the executable client entrypoint;
- broad CoreScripts client watchdog/soft-rejoin behavior was not copied by default because ProfileStore already handles profile session locking/conflict behavior, and client health recovery should be added only when a concrete production need appears.

See [docs/README_ALTAIR_MIGRATION.md](docs/README_ALTAIR_MIGRATION.md) for the detailed migration notes and verification checklist.
See [docs/README_PORTING_GUIDELINES.md](docs/README_PORTING_GUIDELINES.md) for short rules on porting old systems into this architecture.
