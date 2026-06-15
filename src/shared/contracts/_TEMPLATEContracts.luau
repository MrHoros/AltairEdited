--[[
	Template for ByteNetMax gameplay contracts.

	Copy this file into a feature folder under src/shared/contracts/, for example:
	  src/shared/contracts/wave/WavePackets.luau

	Rules:
	- fixed schemas for spawn, unit state, damage, despawn;
	- no server authority logic here;
	- keep UI and lifecycle on BridgeNet2 / GetBridge;
	- register packets in one place so feature code does not call ByteNetMax directly everywhere.

	See docs/README_GETTING_STARTED.md and .junie/guidelines.md (Networking).
]]

-- local ByteNetMax = require(game.ReplicatedStorage.package.ByteNetMax)

-- export type WaveSpawnPayload = {
-- 	waveId: number,
-- 	unitId: number,
-- 	spawnIndex: number,
-- }

-- local WavePackets = ByteNetMax.defineNamespace("Wave", function()
-- 	return {
-- 		SpawnUnit = ByteNetMax.definePacket({ ... }),
-- 	}
-- end)

-- return WavePackets

return nil
