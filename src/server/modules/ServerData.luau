local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.shared.config.GameConfig)
local GetBridge = require(ReplicatedStorage.util.GetBridge)
local IsValidUTF8 = require(ReplicatedStorage.util.IsValidUTF8)
local Logger = require(ReplicatedStorage.util.Logger)
local MergeDictionaries = require(ReplicatedStorage.util.MergeDictionaries)
local ProfileStore = require(ReplicatedStorage.package.ProfileStore)
local ProfileTypes = require(ReplicatedStorage.shared.reflex.ProfileTypes)
local Promise = require(ReplicatedStorage.package.Promise)
local Reflex = require(ReplicatedStorage.package.Reflex)
local Signal = require(ReplicatedStorage.package.Signal)
local gameProfile = require(ReplicatedStorage.shared.reflex.gameProfile)
local playerProfile = require(ReplicatedStorage.shared.reflex.playerProfile)

local sharedFolder: Folder = ReplicatedStorage:WaitForChild("shared") :: Folder
local reflexFolder: Folder = sharedFolder:WaitForChild("reflex") :: Folder

type ProfileTypes = typeof(ProfileTypes)

local function getProfileModules(): { [string]: any }
	local modules: { [string]: any } = {}

	for _index: number, child: Instance in reflexFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			local name: string = child.Name
			if name ~= "gameProfile" and name ~= "clientProfile" and name:match("Profile$") then
				local key: string = name:gsub("Profile$", "")
				modules[key] = require(child) :: any
			end
		end
	end

	return modules
end

export type Data = ProfileTypes.PlayerState

export type ServerPlayerProfile = {
	player: Player,
	profileStore: any,
	producer: ProfileTypes.PlayerProducer,
	nextActionIsReplicated: boolean,
	slices: { string },
}

export type Default = {
	index: number,
	type: string,
	gameProducer: gameProfile.Producer,
	profiles: { [Player]: ServerPlayerProfile? },
	playerDataLoadedEvent: Signal.Signal<Player, ServerPlayerProfile>,
	_started: boolean?,
	_shutdownBound: boolean?,
	_shuttingDown: boolean?,
	GetPlayerProfile: (self: Default, player: Player) -> ServerPlayerProfile?,
	WaitForPlayerProfile: (self: Default, player: Player) -> Promise.TypedPromise<ServerPlayerProfile>,
	GetPlayerProducerAsync: (self: Default, player: Player) -> Promise.TypedPromise<ProfileTypes.PlayerProducer>,
	GetGameProducerAsync: (self: Default) -> Promise.TypedPromise<gameProfile.Producer>,
	SavePlayerProfile: (self: Default, player: Player) -> boolean,
	PlayerAdded: (self: Default, player: Player) -> (),
	PlayerRemoving: (self: Default, player: Player) -> (),
	HandleShutdown: (self: Default) -> (),
	Init: (self: Default) -> (),
}

local ServerData: Default = {} :: Default
ServerData.index = 0
ServerData.type = "controller"
ServerData.profiles = {}
ServerData.playerDataLoadedEvent = Signal.new()

local loadingProfiles: { [Player]: boolean } = {}
local gameStoreReady: { [Player]: boolean } = {}
local endingSessions: { [Player]: boolean } = {}

local PlayerReady = GetBridge("PlayerReady")

local DATASTORE_KEY: string = GameConfig.data.datastoreKey
local PLAYTIME_TICK_SECONDS: number = 10
local SHUTDOWN_RELEASE_GRACE_SECONDS: number = 25

local ReplicateStore = Instance.new("RemoteEvent")
ReplicateStore.Name = "ReplicateStore"
ReplicateStore.Parent = ReplicatedStorage

local ReplicateGameStore = Instance.new("RemoteEvent")
ReplicateGameStore.Name = "ReplicateGameStore"
ReplicateGameStore.Parent = ReplicatedStorage

local GetPlayerData = Instance.new("RemoteFunction")
GetPlayerData.Name = "GetPlayerData"
GetPlayerData.Parent = ReplicatedStorage

local GetGameData = Instance.new("RemoteFunction")
GetGameData.Name = "GetGameData"
GetGameData.Parent = ReplicatedStorage

local function getPlayerKey(userId: number): string
	return GameConfig.data.playerKeyPattern:format(userId)
end

local function formatSeconds(startedAt: number): string
	return string.format("%.3fs", os.clock() - startedAt)
end

local PROFILE_MODULES = getProfileModules()

local function buildDefaultTemplate(profileModules: { [string]: any }): { [string]: any }
	local defaultTemplate = {}

	for key: string, module: any in profileModules do
		if key == "game" then
			continue
		end

		if key == "player" then
			defaultTemplate.player = playerProfile.DEFAULT_STATE
		else
			defaultTemplate[key] = module.DEFAULT_STATE
		end
	end

	if defaultTemplate.player == nil then
		defaultTemplate.player = playerProfile.DEFAULT_STATE
	end

	return defaultTemplate
end

local function buildSaveData(profile: ServerPlayerProfile): { [string]: any }
	local combinedState = profile.producer:getState()
	local saveableData = {}
	local exceptions = {}

	for key: string, module in PROFILE_MODULES do
		if module.SAVE_EXCEPTIONS then
			exceptions[key] = module.SAVE_EXCEPTIONS
		end
	end

	for sliceName, stateSlice in combinedState do
		if not table.find(profile.slices, sliceName) then
			continue
		end

		local data = {}
		local sliceExceptions = exceptions[sliceName] or {}
		for key, value in stateSlice do
			if table.find(sliceExceptions, key) ~= nil then
				continue
			end

			if typeof(value) == "string" and not IsValidUTF8(value) then
				continue
			end

			data[key] = value
		end

		saveableData[sliceName] = data
	end

	if saveableData.player then
		saveableData.player.lastOnline = math.floor(workspace:GetServerTimeNow())
	end

	return saveableData
end

ProfileStore.SetConstant("AUTO_SAVE_PERIOD", 300)

local PLAYER_STORE = ProfileStore.New(DATASTORE_KEY, buildDefaultTemplate(PROFILE_MODULES))

local function syncProfileStoreData(profile: ServerPlayerProfile): ()
	profile.profileStore.Data = buildSaveData(profile)
end

local function clearPlayerRuntimeState(player: Player): ()
	loadingProfiles[player] = nil
	gameStoreReady[player] = nil
	endingSessions[player] = nil
	player:SetAttribute("DataLoaded", nil)
end

GetPlayerData.OnServerInvoke = function(player: Player): ...any
	local startedAt: number = os.clock()

	local existingProfile: ServerPlayerProfile? = ServerData:GetPlayerProfile(player)
	if not existingProfile then
		ServerData:PlayerAdded(player)
	end

	local profile: ServerPlayerProfile? = select(
		2,
		ServerData:WaitForPlayerProfile(player):timeout(GameConfig.data.playerProfileInvokeTimeout, false):await()
	)
	if not profile then
		Logger.warn(`GetPlayerData: no profile found for {player.Name} after {formatSeconds(startedAt)}`)

		return
	end

	return profile.producer:getState()
end

GetGameData.OnServerInvoke = function(player: Player): ...any
	local startedAt: number = os.clock()

	if player then
		gameStoreReady[player] = true
	end

	if not ServerData.gameProducer then
		Logger.warn(`GetGameData: game producer missing for {player.Name}; returning default after {formatSeconds(startedAt)}`)

		return gameProfile.DEFAULT_STATE
	end

	return ServerData.gameProducer:getState()
end

function ServerData:GetPlayerProfile(player: Player): ServerPlayerProfile?
	return self.profiles[player]
end

function ServerData:WaitForPlayerProfile(player: Player): Promise.TypedPromise<ServerPlayerProfile>
	return Promise.new(
		function(resolve: (ServerPlayerProfile) -> (), _reject: (unknown) -> (), onCancel: (() -> ()) -> ()): ()
			local profile = self:GetPlayerProfile(player)
			local connection

			if profile then
				resolve(profile)

				return
			end

			connection = self.playerDataLoadedEvent:Connect(function(newPlayer: Player, data: ServerPlayerProfile): ()
				if newPlayer ~= player then
					return
				end

				connection:Disconnect()
				resolve(data)
			end)

			onCancel(function(): ()
				if connection then
					connection:Disconnect()
				end
			end)
		end
	)
end

function ServerData:GetPlayerProducerAsync(player: Player): Promise.TypedPromise<ProfileTypes.PlayerProducer>
	return Promise.new(function(resolve: (ProfileTypes.PlayerProducer) -> ()): ()
		local profile = self:WaitForPlayerProfile(player):expect()
		resolve(profile and profile.producer or nil)
	end)
end

function ServerData:GetGameProducerAsync(): Promise.TypedPromise<gameProfile.Producer>
	return Promise.new(function(resolve: (gameProfile.Producer) -> (), reject: (string) -> ()): ()
		if not self.gameProducer then
			reject(
				`Game producer not initialized yet! Change calling controller index to higher number than {self.index}!`
			)
		end

		resolve(self.gameProducer)
	end)
end

function ServerData:SavePlayerProfile(player: Player): boolean
	local profile: ServerPlayerProfile? = self:GetPlayerProfile(player)
	if not profile or not profile.profileStore:IsActive() then
		return false
	end

	syncProfileStoreData(profile)
	profile.profileStore:Save()

	return true
end

function ServerData:PlayerAdded(player: Player): ()
	if self.profiles[player] then
		return
	end

	if loadingProfiles[player] then
		return
	end

	loadingProfiles[player] = true
	local startedAt: number = os.clock()
	local playerKey: string = getPlayerKey(player.UserId)

	local profileModules = PROFILE_MODULES
	local profileStore = PLAYER_STORE:StartSessionAsync(playerKey, {
		Cancel = function(): boolean
			local shouldCancel: boolean = not player:IsDescendantOf(Players) or self._shuttingDown == true
			if shouldCancel then
				Logger.warn(`ServerData: StartSessionAsync cancel requested for {player.Name}`)
			end

			return shouldCancel
		end,
	})

	if not profileStore then
		Logger.warn(`ServerData: StartSessionAsync failed for {player.Name} after {formatSeconds(startedAt)}`)
		player:Kick("Failed to load your data. Please try again later.")
		clearPlayerRuntimeState(player)

		return
	end

	profileStore:AddUserId(player.UserId)
	profileStore:Reconcile()

	profileStore.OnSessionEnd:Connect(function(): ()
		local isExpectedEnd = endingSessions[player] == true or self._shuttingDown == true
		self.profiles[player] = nil
		clearPlayerRuntimeState(player)

		if isExpectedEnd then
			return
		end

		Logger.warn(`ServerData: unexpected session end for {player.Name}`)

		if player:IsDescendantOf(Players) then
			player:Kick("Your data has been loaded on another server.")
		end
	end)

	profileStore.OnSave:Connect(function(): ()
		local activeProfile: ServerPlayerProfile? = self.profiles[player]
		if activeProfile and activeProfile.profileStore:IsActive() then
			syncProfileStoreData(activeProfile)
		end
	end)

	if not player:IsDescendantOf(Players) then
		Logger.warn(`ServerData: {player.Name} left before profile setup completed`)
		endingSessions[player] = true
		profileStore:EndSession()
		clearPlayerRuntimeState(player)

		return
	end

	local data = profileStore.Data

	local producers = {}
	local playerData = data.player or {}

	playerData.ready = false
	playerData.userId = player.UserId

	producers.player = playerProfile.CreateProducer(MergeDictionaries(playerProfile.DEFAULT_STATE, playerData))
	local slices: { string } = {}
	table.insert(slices, "player")

	for key: string, module: any in profileModules do
		if key == "player" or key == "game" then
			continue
		end

		table.insert(slices, key)

		local initialState
		if data[key] then
			initialState = MergeDictionaries(module.DEFAULT_STATE, data[key])
		else
			initialState = module.DEFAULT_STATE
		end

		producers[key] = module.CreateProducer(initialState)
	end

	local combinedProducer: ProfileTypes.PlayerProducer =
		Reflex.combineProducers(producers) :: ProfileTypes.PlayerProducer

	local profile: ServerPlayerProfile = {
		player = player,
		profileStore = profileStore,
		producer = combinedProducer,
		nextActionIsReplicated = false,
		slices = slices,
	}

	local replicateMiddleware: Reflex.Middleware = function(): ((...any) -> any, string) -> (...any) -> any
		return function(dispatch: (...any) -> any, name: string): (...any) -> any
			return function(...: any): any
				if profile.nextActionIsReplicated then
					profile.nextActionIsReplicated = false
					return dispatch(...)
				end

				ReplicateStore:FireClient(player, {
					name = name,
					arguments = { ... },
				})

				return dispatch(...)
			end
		end
	end

	profile.producer:applyMiddleware(replicateMiddleware)

	self.profiles[player] = profile
	self.playerDataLoadedEvent:Fire(player, profile)
	player:SetAttribute("DataLoaded", true)

	profile.producer.secureFirstTime()

	loadingProfiles[player] = nil
end

function ServerData:PlayerRemoving(player: Player): ()
	local profile: ServerPlayerProfile? = self.profiles[player]
	if not profile then
		clearPlayerRuntimeState(player)
		return
	end

	if (profile.producer :: any).secureSetLastSeenTimestamp then
		(profile.producer :: any).secureSetLastSeenTimestamp()
	end

	endingSessions[player] = true
	syncProfileStoreData(profile)
	profile.profileStore:EndSession()
	self.profiles[player] = nil
	clearPlayerRuntimeState(player)
end

function ServerData:HandleShutdown(): ()
	if self._shuttingDown == true then
		return
	end

	self._shuttingDown = true

	local onlinePlayers: { Player } = Players:GetPlayers()
	if #onlinePlayers == 0 then
		return
	end

	Logger.warn(`BindToClose: releasing {#onlinePlayers} online profile(s) before shutdown`)

	for _, player: Player in onlinePlayers do
		self:PlayerRemoving(player)
	end

	local shutdownStartedAt: number = os.clock()
	while os.clock() - shutdownStartedAt < SHUTDOWN_RELEASE_GRACE_SECONDS do
		local hasPendingProfiles: boolean = false

		for _, player: Player in Players:GetPlayers() do
			if self.profiles[player] or loadingProfiles[player] then
				hasPendingProfiles = true
				break
			end
		end

		if not hasPendingProfiles then
			break
		end

		task.wait(0.1)
	end
end

function ServerData:Init(): ()
	if self._started == true then
		return
	end

	self._started = true

	PlayerReady:Connect(function(player: Player): ()
		ServerData:GetPlayerProducerAsync(player):expect().setPlayerReady()
	end)

	task.spawn(function(): ()
		while true do
			task.wait(PLAYTIME_TICK_SECONDS)

			for _player: Player, profile: ServerPlayerProfile in self.profiles do
				if profile and profile.producer then
					if (profile.producer :: any).secureAddTimePlayedSeconds then
						(profile.producer :: any).secureAddTimePlayedSeconds(PLAYTIME_TICK_SECONDS)
					end

					if profile.profileStore:IsActive() then
						syncProfileStoreData(profile)
					end
				end
			end
		end
	end)

	self.gameProducer = gameProfile.CreateProducer(gameProfile.DEFAULT_STATE)

	local nextActionIsReplicated: boolean = false

	local replicateMiddleware: Reflex.Middleware = function(): ((...any) -> any, string) -> (...any) -> any
		return function(dispatch: (...any) -> any, name: string): (...any) -> any
			return function(...: any): any
				if nextActionIsReplicated then
					nextActionIsReplicated = false
					return dispatch(...)
				end

				local payload = {
					name = name,
					arguments = { ... },
				}

				for _index: number, player: Player in Players:GetPlayers() do
					if gameStoreReady[player] then
						ReplicateGameStore:FireClient(player, payload)
					end
				end

				return dispatch(...)
			end
		end
	end

	self.gameProducer:applyMiddleware(replicateMiddleware)

	ReplicateStore.OnServerEvent:Connect(function(player: Player, data: { name: string, [string]: any }): ()
		if type(data) ~= "table" then
			return
		end

		local actionNameAny: any = data.name
		local actionName: string? = type(actionNameAny) == "string" and actionNameAny or nil
		if not actionName then
			return
		end

		local isSecureAction: number? = actionName:find("^secure")
		if isSecureAction then
			Logger.warn("Player tried to replicate secure reflex action", actionName)

			return
		end

		local profile: ServerPlayerProfile? = self:GetPlayerProfile(player)
		if not profile then
			return
		end

		local action: any = (profile.producer :: any)[actionName]
		if type(action) ~= "function" then
			Logger.warn("Player tried to replicate unknown reflex action", actionName)

			return
		end

		local arguments: { any } = if type(data.arguments) == "table" then data.arguments else {}

		profile.nextActionIsReplicated = true
		action(unpack(arguments))
	end)

	ReplicateGameStore.OnServerEvent:Connect(function(_player: Player, data: { name: string, [string]: any }): ()
		if type(data) ~= "table" then
			return
		end

		local actionNameAny: any = data.name
		local actionName: string? = type(actionNameAny) == "string" and actionNameAny or nil
		if not actionName then
			return
		end

		local isSecureAction: number? = actionName:find("^secure")
		if isSecureAction then
			Logger.warn("Player tried to replicate secure reflex action", actionName)

			return
		end

		local action: any = self.gameProducer[actionName]
		if type(action) ~= "function" then
			Logger.warn("Player tried to replicate unknown game reflex action", actionName)

			return
		end

		local arguments: { any } = if type(data.arguments) == "table" then data.arguments else {}

		nextActionIsReplicated = true
		action(unpack(arguments))
	end)

	if not self._shutdownBound then
		self._shutdownBound = true
		game:BindToClose(function(): ()
			self:HandleShutdown()
		end)
	end
end

return ServerData
