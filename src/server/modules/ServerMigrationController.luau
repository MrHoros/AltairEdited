local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local InitializerTypes = require(ReplicatedStorage.shared.types.InitializerTypes)
local Logger = require(ReplicatedStorage.util.Logger)
local ServerData = require(ServerScriptService.server.modules.ServerData)

export type MigrationMessage = {
	action: string?,
	force: boolean?,
	sourceJobId: string?,
	sourcePlaceVersion: number?,
	windowSeconds: number?,
}

export type ServerMigrationController = {
	index: number?,
	type: string?,
	PlayerAdded: (self: ServerMigrationController, player: Player) -> (),
	QueueMigration: (self: ServerMigrationController, messageData: MigrationMessage) -> (),
	SavePlayers: (self: ServerMigrationController, players: { Player }) -> (),
	Start: (self: ServerMigrationController) -> (),
	TeleportPlayers: (self: ServerMigrationController, players: { Player }) -> boolean,
	isMigrating: boolean,
	migrationStartedAt: number?,
	path: InitializerTypes.ServerPath,
}

local ServerMigrationController: ServerMigrationController = {} :: ServerMigrationController
ServerMigrationController.type = "controller"
ServerMigrationController.index = 3
ServerMigrationController.isMigrating = false

local MIGRATE_TOPIC: string = "ServerMigrate_v1"
local MIGRATE_ACTION: string = "migrate"
local DATA_LOAD_TIMEOUT_SECONDS: number = 12
local SAVE_SETTLE_SECONDS: number = 1
local TELEPORT_RETRY_COUNT: number = 3
local TELEPORT_RETRY_DELAY_SECONDS: number = 2
local TELEPORT_FAILURE_MESSAGE: string = "Server update in progress. Please rejoin."

local randomGenerator: Random = Random.new()

local function getOnlinePlayers(players: { Player }): { Player }
	local onlinePlayers: { Player } = {}

	for _index: number, player: Player in players do
		if player:IsDescendantOf(Players) then
			table.insert(onlinePlayers, player)
		end
	end

	return onlinePlayers
end

local function shouldIgnoreMigration(messageData: MigrationMessage): boolean
	if messageData.action ~= MIGRATE_ACTION then
		return true
	end

	if messageData.sourceJobId == game.JobId then
		return true
	end

	if messageData.force == true then
		return false
	end

	local sourcePlaceVersion: number? = messageData.sourcePlaceVersion
	if not sourcePlaceVersion or sourcePlaceVersion <= game.PlaceVersion then
		return true
	end

	return false
end

function ServerMigrationController:SavePlayers(players: { Player }): ()
	for _index: number, player: Player in players do
		if not player:IsDescendantOf(Players) then
			continue
		end

		local hasProfile: boolean = ServerData:GetPlayerProfile(player) ~= nil
		if not hasProfile then
			ServerData:WaitForPlayerProfile(player):timeout(DATA_LOAD_TIMEOUT_SECONDS, false):await()
		end

		if not ServerData:SavePlayerProfile(player) then
			Logger.warn(`ServerMigrationController: failed to save profile before migration player={player.Name}`)
		end
	end
end

function ServerMigrationController:TeleportPlayers(players: { Player }): boolean
	for attempt: number = 1, TELEPORT_RETRY_COUNT do
		local onlinePlayers: { Player } = getOnlinePlayers(players)
		if #onlinePlayers == 0 then
			return true
		end

		local success: boolean, err: any = pcall(function(): ()
			TeleportService:TeleportAsync(game.PlaceId, onlinePlayers)
		end)

		if success then
			return true
		end

		Logger.warn(
			`ServerMigrationController: TeleportAsync attempt {attempt}/{TELEPORT_RETRY_COUNT} failed: {tostring(err)}`
		)

		if attempt < TELEPORT_RETRY_COUNT then
			task.wait(TELEPORT_RETRY_DELAY_SECONDS)
		end
	end

	for _index: number, player: Player in getOnlinePlayers(players) do
		player:Kick(TELEPORT_FAILURE_MESSAGE)
	end

	return false
end

function ServerMigrationController:QueueMigration(messageData: MigrationMessage): ()
	if self.isMigrating then
		return
	end

	if shouldIgnoreMigration(messageData) then
		return
	end

	self.isMigrating = true
	self.migrationStartedAt = os.clock()

	local windowSeconds: number = math.max(0, messageData.windowSeconds or 0)
	local delaySeconds: number = windowSeconds > 0 and randomGenerator:NextNumber(0, windowSeconds) or 0

	task.delay(delaySeconds, function(): ()
		local players: { Player } = Players:GetPlayers()
		if #players == 0 then
			return
		end

		Logger.warn(
			`ServerMigrationController: migrating {#players} player(s), currentVersion={game.PlaceVersion}, sourceVersion={tostring(
				messageData.sourcePlaceVersion
			)}`
		)

		self:SavePlayers(players)
		task.wait(SAVE_SETTLE_SECONDS)
		self:TeleportPlayers(players)
	end)
end

function ServerMigrationController:PlayerAdded(player: Player): ()
	if not self.isMigrating then
		return
	end

	task.spawn(function(): ()
		ServerData:WaitForPlayerProfile(player):timeout(DATA_LOAD_TIMEOUT_SECONDS, false):await()
		self:SavePlayers({ player })
		self:TeleportPlayers({ player })
	end)
end

function ServerMigrationController:Start(): ()
	local success: boolean, err: any = pcall(function(): ()
		MessagingService:SubscribeAsync(MIGRATE_TOPIC, function(message: { Data: any }): ()
			if typeof(message.Data) ~= "table" then
				return
			end

			self:QueueMigration(message.Data :: MigrationMessage)
		end)
	end)

	if not success then
		Logger.warn(`ServerMigrationController: failed to subscribe to migration topic: {tostring(err)}`)
	end
end

return ServerMigrationController
