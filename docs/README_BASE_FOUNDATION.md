# Base Foundation

`ServerBaseController` and `server/classes/Base.luau` are **built-in starter foundation**, not a temporary port from another repo.

They provide player base/plot assignment for defense-style games (bases, waves, tower defense, zombie horde modes).

The controller is enabled by default because the starter place is expected to include the required world and model instances.

## Runtime Requirements

The place must provide:

- `Workspace.BaseInitSlot` containing numbered `BasePart` children;
- `ReplicatedStorage.shared.model.BaseComponents.PlayerBase`;
- optional `SpawnPosition`, `OwnerBoard.Board.SurfaceGui.Username`, and
  `OwnerBoard.Board2.SurfaceGui.ImageLabel` descendants inside the base model.

## Disable For Games Without Plots

If your game does not use assigned bases:

1. Add `"ServerBaseController"` to `src/server/serverConfig/ServerInitConfig.luau`.
2. Remove unused base assets from the place when convenient.

## Customizing For Your Game

Keep the controller thin. When your world model differs:

- rewrite `server/classes/Base.luau` around your instances and attributes;
- keep reservation → profile wait → claim → release lifecycle;
- do not move base authority into `shared`.

Do not attach unrelated foundation systems to this module.
