# Porting Guidelines

Use this checklist when moving old CoreScripts/local systems into this Altair-derived architecture.

## 1. Port behavior, not folder shape

Do not copy an old folder tree just because it worked before. First identify the actual behavior:

- what data it owns;
- what remotes/signals it uses;
- what player lifecycle callbacks it needs;
- what UI or world instances it expects;
- what other controllers/services it depends on.

Then place it in the current architecture based on ownership.

## 2. Keep runtime boundaries strict

Use these default locations:

- `src/client/exec`: client entrypoints only;
- `src/client/modules`: client controllers, components, local runtime systems;
- `src/client/ui`: UI-facing modules and screen/widget behavior;
- `src/server/modules`: server controllers/services;
- `src/server/serverConfig`: server-only runtime config and execution policy;
- `src/shared/config`: pure constants that both client and server may read;
- `src/shared/reflex`: Reflex state slices and producer definitions;
- `src/shared/types`: type-only/shared contracts;
- `src/util`: small infrastructure helpers only.

Avoid putting server-only logic in `shared`. If a module touches `ServerScriptService`, server-only services, datastores, receipt processing, or trusted game authority, it belongs on the server.

## 3. Avoid controller-to-controller coupling

Old systems often call other controllers directly. Prefer one of these instead:

- depend on a smaller service/facade;
- expose a narrow method on an existing service;
- move shared pure logic into `shared/config` or another pure shared module;
- use explicit events/signals for cross-system notifications.

Direct `self.path.controller.OtherController` usage is acceptable for small compatibility bridges, but do not grow new systems around it.

## 4. Data migration rules

Do not copy old `ServerData` patterns into new systems.

For data-backed features:

- add or update a Reflex profile slice first;
- define defaults in the slice;
- add `SAVE_EXCEPTIONS` when a field should not persist;
- add a focused migration/sanitizer only for real legacy data shape;
- read/write through `ServerData:GetPlayerProducerAsync(player)`;
- never write directly into `ProfileStore.Data` from feature modules.

`ServerData` owns converting producer state into persisted profile data.

## 5. Networking rules

Do not scatter new raw remotes across feature code.

For now, keep existing Altair replication remotes for Reflex state:

- `GetPlayerData`;
- `GetGameData`;
- `ReplicateStore`;
- `ReplicateGameStore`.

For new gameplay remotes, prefer a small wrapper/registry module so the project can later move away from the current bridge backend without rewriting feature code.

## 6. Bootstrap rules

A ported module may use these lifecycle methods:

- `Init`;
- `Start`;
- `PlayerAdded`;
- `PlayerRemoving`;
- `CharacterAdded`;
- `CharacterAppearanceLoaded`;
- `Died`;
- `Physics`;
- `Stepped`.

Use `index` only when ordering is truly required. Lower `index` means earlier priority startup. Avoid using `index` just to hide race conditions; prefer explicit async waits such as `ServerData:GetPlayerProducerAsync(player)`.

## 7. UI porting rules

Keep UI behavior client-owned.

Good targets:

- screen-level modules in `src/client/ui`;
- client controllers in `src/client/modules`;
- pure display config in `src/shared/config`.

Do not let UI modules require server modules. If UI needs server state, expose it through replicated Reflex state or a narrow remote/query.

## 8. Monetization rules

Do not port a large old monetization controller as-is.

Preferred shape:

- config describes product/pass identifiers;
- server-only exec handlers perform purchase effects;
- receipt processing stays narrow;
- feature-specific grants live near the feature service, not inside one giant monetization controller.

ProfileStore helps verify saved data through `LastSavedData`, but purchase idempotency still needs deliberate receipt handling.

## 9. Asset and Studio-instance assumptions

Before porting a script, list required runtime instances:

- GUI names;
- tags;
- attributes;
- folders under `ReplicatedStorage.shared.model`;
- sounds;
- animations;
- tools;
- workspace models.

If the asset is not source-backed, document it or create a smoke check. Do not leave hidden Studio-only dependencies undocumented.

## 10. Porting order

Use this order for each old system:

1. Move pure config/types.
2. Move or recreate Reflex slices.
3. Move small util dependencies.
4. Move server authority logic.
5. Move client/UI logic.
6. Add remotes or bridge wrappers only after ownership is clear.
7. Run a Studio smoke test.
8. Remove temporary compatibility shims.

## 11. Red flags

Pause and refactor if a ported module:

- requires both `ServerScriptService` and client UI;
- writes directly to profile data;
- creates remotes deep inside feature code;
- depends on three or more controllers;
- requires `Workspace` from `shared`;
- silently assumes a Studio-only asset exists;
- needs `task.wait(...)` to make initialization order work;
- copies a large old module without deleting unused branches.

These are usually signs that the old system should be split before it enters the new architecture.

