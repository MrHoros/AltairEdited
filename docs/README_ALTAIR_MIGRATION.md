# Altair Migration Notes

> Historical reference for maintainers. New games should start from this repository directly.
> Primary onboarding: [README_GETTING_STARTED.md](README_GETTING_STARTED.md).

## Source Baseline

This branch starts from the Altair `3.0.2` lineage. The exact baseline commit is
`39349d18f1afc01b84b7e7f4cbb6dde6ef0ad982` (`2026-05-31`, `Merge pull request #1 from kardavx/macos-support`).

Version note: the repository history contains `88637da` with message `Update to Altair 3.0.2`, followed by a few commits including the macOS shell-script merge. The old `wally.toml` package version value was `2.0.0`, but that is stale package metadata and is not the actual Altair baseline version.

The original Altair baseline already had the better project topology for this migration:

- `src/client` is mounted into `ReplicatedStorage.client`.
- Only `src/client/exec` is mounted into `StarterPlayerScripts`.
- `src/preload` is mounted into `ReplicatedFirst`.
- shared runtime modules stay in `ReplicatedStorage.shared`.

That topology is intentionally preserved. The local CoreScripts layout mounted the whole client into `StarterPlayerScripts`; this branch does not adopt that, because it makes client modules behave like executable runtime code instead of library code.

## ProfileService to ProfileStore

`wally.toml` now uses:

```toml
ProfileStore = "2jammers/profilestore@0.1.0"
```

The old dependency:

```toml
ProfileService = "brittonfischer/profileservice@2.1.5"
```

was removed.

The main data module changed from `ProfileService.GetProfileStore(...):LoadProfileAsync(...)` to the newer ProfileStore session API:

```lua
local playerStore = ProfileStore.New(DATASTORE_KEY, defaultTemplate)
local profile = playerStore:StartSessionAsync(playerKey, {
	Cancel = function()
		return player left or server is shutting down
	end,
})
```

Profiles are now closed with:

```lua
profile:EndSession()
```

instead of:

```lua
profile:Release()
```

This follows ProfileStore's current contract: active sessions autosave, session locks are handled by ProfileStore, and the developer must end sessions when finished.

## What ProfileStore Replaces

ProfileStore already covers several concerns that were previously tempting to implement manually:

- profile session locking;
- faster conflict resolution between servers using MessagingService;
- autosave;
- final save through `EndSession`;
- session-end notification through `OnSessionEnd`;
- last-save hooks through `OnLastSave`;
- cancel conditions while waiting for a session.

Because of that, this branch does not copy the full CoreScripts soft-rejoin/client-health watchdog into the foundation.

## What ProfileStore Does Not Replace

ProfileStore does not manage application boot order. It does not know whether controllers finished `Init` or `Start`, whether tag classes were created, or whether player lifecycle callbacks are safe to dispatch.

For that reason, the server bootstrap was still upgraded with:

- priority controller sequence;
- regular controller barrier;
- lifecycle timeout handling;
- progress logging;
- summary logging;
- `PlayerAdded` dispatch only after all controllers complete their startup phases.

This is separate from data persistence. ProfileStore protects profile sessions; the bootstrap barrier protects app initialization order.

## ServerData Contract Kept

The public contract expected by the existing Altair client/server code is preserved:

- `GetPlayerProfile(player)`;
- `WaitForPlayerProfile(player)`;
- `GetPlayerProducerAsync(player)`;
- `GetGameProducerAsync()`;
- `playerDataLoadedEvent`;
- `PlayerAdded(player)`;
- `PlayerRemoving(player)`.

Client replication remotes are also preserved:

- `GetPlayerData`;
- `GetGameData`;
- `ReplicateStore`;
- `ReplicateGameStore`.

That means existing `ClientData`, Cmdr commands, and monetization code can continue using the same facade while the underlying persistence implementation changes.

## ServerData Details

The data template is still assembled from `src/shared/reflex/*Profile.luau` modules, excluding `gameProfile` and `clientProfile`, matching the original Altair behavior.

When a player joins:

1. `loadingProfiles[player]` prevents duplicate session starts.
2. `ProfileStore:StartSessionAsync(...)` starts the profile session.
3. `Cancel` stops the request if the player leaves or the server starts shutting down.
4. `profile:AddUserId(player.UserId)` keeps GDPR erasure support.
5. `profile:Reconcile()` backfills template fields.
6. Reflex producers are rebuilt from the loaded slices.
7. Replication middleware mirrors producer actions to the client.
8. `DataLoaded` is set on the player.

When a player leaves:

1. transient runtime state is cleared;
2. producer state is converted back into saveable data;
3. invalid UTF-8 string values are skipped;
4. slice-level `SAVE_EXCEPTIONS` are respected;
5. `lastOnline` is updated;
6. `profile:EndSession()` performs the final save and closes the ProfileStore session.

## Session-End Behavior

`ProfileStore.OnSessionEnd` is used to distinguish profile ownership loss from normal local cleanup.

If the session ends unexpectedly while the player is still in the server, the player is kicked with the existing "loaded on another server" style message.

If the session ends because this server called `EndSession` during `PlayerRemoving` or shutdown, the branch does not kick the player.

## Bootstrap Details

`src/server/main.server.luau` now keeps Altair's bridge bootstrap:

```lua
_GetBridgeFunction
```

and adds the CoreScripts-style lifecycle orchestration:

- modules are discovered before lifecycle dispatch;
- `index` controllers run sequentially;
- non-index controllers run as a barrier;
- both `Init` and `Start` phases have timeout protection;
- logs include slowest controller and timeout counts;
- `Players.PlayerAdded` waits for `controllersReadyEvent`.

The server still loads `ReplicatedStorage.shared.modules`. This is not ideal as a long-term ownership boundary, but it is required in this intermediate branch because Altair currently has shared modules such as `TagManager`, `Conditions`, `CooldownManager`, `CacheManager`, and `QueueManager` that expect `path` injection or lifecycle callbacks.

## Client Bootstrap Decision

The client bootstrap was not replaced wholesale with CoreScripts.

Reason:

- Altair already has the correct `ReplicatedStorage.client` plus `src/client/exec` topology.
- The CoreScripts client watchdog and loading heartbeat were built around a different local project shape.
- ProfileStore does not require a client heartbeat to protect data sessions.

The current recommendation is to add client loading health only after a real production failure mode appears, such as clients stalling during preload after data has already loaded. At that point, add it as a small `ClientSessionHealth` service rather than mixing it directly into the main bootstrap.

## Preload Decision

Altair preload is kept as the foundation because it already:

- disables CoreGui during loading;
- disables character controls;
- preloads GUI image assets;
- waits for `ClientData:GetPlayerProducerAsync()`;
- sends `PlayerReady` after data is available.

The local CoreScripts loading-screen animation can still be ported later, but it is visual/UX behavior, not required for the ProfileStore migration.

## Not Ported Yet

These CoreScripts ideas were intentionally not copied into this branch:

- full client health watchdog;
- soft rejoin;
- leaderboard sync loop;
- large data sanitizers for domain-specific saves;
- local monetization controller shape;
- local client bootstrap replacement.

They should be ported only if the target game needs them. ProfileStore reduces the need for manual session-recovery code, but it does not remove the need for game-specific data migrations.

## Verification Checklist

Run after dependency install:

```bash
bash update.sh
```

Then analyze the changed scripts individually:

```text
.\luau-lsp.exe analyze src\server\modules\ServerData.luau
.\luau-lsp.exe analyze src\server\main.server.luau
```

Studio smoke test:

1. Start Rojo with `bash serve.sh`.
2. Join in Studio with API services enabled or ProfileStore mock strategy configured.
3. Confirm server logs show `ServerBootstrap[Init]` and `ServerBootstrap[Start]` summaries.
4. Confirm `GetPlayerData` returns player state.
5. Confirm `PlayerReady` sets `player.ready`.
6. Leave the game and confirm no unexpected session-end kick appears.

## Known Follow-Ups

- Decide whether to use `ProfileStore.Mock` in Studio to avoid writing live datastore keys.
- Decide whether to move ProfileStore into `ServerPackages` or keep the Wally shared package mount.
- Eventually stop auto-loading `ReplicatedStorage.shared.modules` from server bootstrap, but only after shared modules are split into explicit server/client ownership.
- Add domain-specific migrations only when the migrated CoreScripts configs/profiles require them.
- Keep optional game-specific ports disabled by default until the target game provides their required Studio instances.

For future feature ports, use [Porting Guidelines](README_PORTING_GUIDELINES.md).
