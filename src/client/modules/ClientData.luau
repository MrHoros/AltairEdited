local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder: Folder = ReplicatedStorage:WaitForChild("shared") :: Folder
local _typesFolder: Folder = sharedFolder:WaitForChild("types") :: Folder
local reflexFolder: Folder = sharedFolder:WaitForChild("reflex") :: Folder

local InitializerTypes = require(ReplicatedStorage.shared.types.InitializerTypes)
local LocalPlayer = require(ReplicatedStorage.util.LocalPlayer)
local Logger = require(ReplicatedStorage.util.Logger)
local MergeDictionaries = require(ReplicatedStorage.util.MergeDictionaries)
local ProfileTypes = require(ReplicatedStorage.shared.reflex.ProfileTypes)
local Promise = require(ReplicatedStorage.package.Promise)
local Reflex = require(ReplicatedStorage.package.Reflex)
local Signal = require(ReplicatedStorage.package.Signal)
local clientProfile = require(ReplicatedStorage.shared.reflex.clientProfile)
local gameProfile = require(ReplicatedStorage.shared.reflex.gameProfile)

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

export type Default = {
	index: number,
	type: string,
	path: InitializerTypes.ClientPath,
	clientProducer: clientProfile.Producer,
	playerProducer: ProfileTypes.PlayerProducer,
	gameProducer: gameProfile.Producer,
	isPlayerDataLoaded: boolean,
	isGameDataLoaded: boolean,
	playerDataLoadedSignal: Signal.Signal<()>,
	gameDataLoadedSignal: Signal.Signal<()>,
	GetPlayerProducerAsync: (self: Default) -> Promise.TypedPromise<ProfileTypes.PlayerProducer>,
	GetClientProducerAsync: (self: Default) -> Promise.TypedPromise<clientProfile.Producer>,
	GetGameProducerAsync: (self: Default) -> Promise.TypedPromise<gameProfile.Producer>,
	PlayerAdded: (self: Default, player: Player) -> (),
	Init: (self: Default) -> (),
}

local ClientData: Default = {
	index = 0,
	type = "controller",
	isPlayerDataLoaded = false,
	isGameDataLoaded = false,
	playerDataLoadedSignal = Signal.new(),
	gameDataLoadedSignal = Signal.new(),
} :: Default

local playerDataQueue: number = 0
local gameDataQueue: number = 0
local pendingPlayerReplicationEvents: { { name: string, arguments: { any } } } = {}
local pendingGameReplicationEvents: { { name: string, arguments: { any } } } = {}

local function waitForSignal<T>(signal: Signal.Signal<T>, getValue: () -> T?): Promise.TypedPromise<T>
	return Promise.new(function(resolve: (T) -> (), _reject: (unknown) -> (), onCancel: (() -> ()) -> ()): ()
		local value: T? = getValue()
		if value then
			resolve(value)

			return
		end

		local connection
		connection = signal:Connect(function(): ()
			local newValue: T? = getValue()
			if not newValue then
				return
			end

			connection:Disconnect()
			resolve(newValue)
		end)

		onCancel(function(): ()
			if connection then
				connection:Disconnect()
			end
		end)
	end)
end

local function CreateClientProducer(data: any): Reflex.Producer<any, any>
	local producer: Reflex.Producer<any, any> = Reflex.createProducer(data, {})

	return producer
end

local function applyPlayerReplicationEvent(self: Default, data: { name: string, arguments: { any } }): ()
	local actionNameAny: any = data.name
	local actionName: string? = type(actionNameAny) == "string" and actionNameAny or nil
	if not actionName then
		return
	end

	local action: any = self.playerProducer[actionName]
	if type(action) ~= "function" then
		Logger.warn("Unknown action:", actionName)

		return
	end

	local arguments: { any } = if type(data.arguments) == "table" then data.arguments else {}

	playerDataQueue += 1

	action(unpack(arguments))
end

local function applyGameReplicationEvent(self: Default, data: { name: string, arguments: { any } }): ()
	local actionNameAny: any = data.name
	local actionName: string? = type(actionNameAny) == "string" and actionNameAny or nil
	if not actionName then
		return
	end

	local action: any = self.gameProducer[actionName]
	if type(action) ~= "function" then
		Logger.warn("Unknown game action:", actionName)

		return
	end

	local arguments: { any } = if type(data.arguments) == "table" then data.arguments else {}

	gameDataQueue += 1

	action(unpack(arguments))
end

function ClientData:GetPlayerProducerAsync(): Promise.TypedPromise<ProfileTypes.PlayerProducer>
	return waitForSignal(self.playerDataLoadedSignal, function(): ProfileTypes.PlayerProducer?
		return self.isPlayerDataLoaded and self.playerProducer or nil
	end)
end

function ClientData:GetClientProducerAsync(): Promise.TypedPromise<clientProfile.Producer>
	return waitForSignal(self.playerDataLoadedSignal, function(): clientProfile.Producer?
		return self.clientProducer
	end)
end

function ClientData:GetGameProducerAsync(): Promise.TypedPromise<gameProfile.Producer>
	return waitForSignal(self.gameDataLoadedSignal, function(): gameProfile.Producer?
		return self.isGameDataLoaded and self.gameProducer or nil
	end):andThen(function(producer: gameProfile.Producer): gameProfile.Producer
		if producer then
			return producer
		end

		error(`Game producer not initialized yet! Change calling controller index to higher number than {self.index}!`)
	end)
end

function ClientData:PlayerAdded(player: Player): ()
	if player ~= LocalPlayer then
		return
	end
end

function ClientData:Init(): ()
	self.clientProducer = CreateClientProducer(clientProfile.DEFAULT_STATE)

	local function loadPlayerData(): ()
		local playerData = ReplicatedStorage:WaitForChild("GetPlayerData"):InvokeServer()
		if not playerData then
			Logger.warn("ClientData: GetPlayerData returned nil; retrying")
			task.wait(0.5)

			return loadPlayerData()
		end

		local replicateMiddleware = function(): ()
			return function(dispatch: (...any) -> (...any) -> any, name: string): (...any) -> any
				return function(...: any): any
					if playerDataQueue >= 1 then
						playerDataQueue -= 1

						return dispatch(...)
					end

					ReplicatedStorage:WaitForChild("ReplicateStore"):FireServer({
						name = name,
						arguments = { ... },
					})

					return dispatch(...)
				end
			end
		end

		local modules = getProfileModules()
		local producers = {}

		for key: string, module: any in modules do
			local state = playerData[key]
			local initialState = state and MergeDictionaries(module.DEFAULT_STATE, state) or module.DEFAULT_STATE

			producers[key] = module.CreateProducer(initialState)
		end

		self.playerProducer = Reflex.combineProducers(producers) :: ProfileTypes.PlayerProducer

		self.playerProducer:applyMiddleware(replicateMiddleware)
		self.isPlayerDataLoaded = true

		for _, data: { name: string, arguments: { any } } in pendingPlayerReplicationEvents do
			applyPlayerReplicationEvent(self, data)
		end

		table.clear(pendingPlayerReplicationEvents)
		self.playerDataLoadedSignal:Fire()

		return
	end

	local function loadGameData(): (() -> ())?
		local gameData = ReplicatedStorage:WaitForChild("GetGameData"):InvokeServer()
		if not gameData then
			Logger.warn("ClientData: GetGameData returned nil; retrying")
			task.wait(0.2)

			return loadGameData()
		end

		local replicateMiddleware = function(): ()
			return function(dispatch: (...any) -> (...any) -> any, name: string): (...any) -> any
				return function(...: any): (...any) -> any
					if gameDataQueue >= 1 then
						gameDataQueue -= 1

						return dispatch(...)
					end

					ReplicatedStorage:WaitForChild("ReplicateGameStore"):FireServer({
						name = name,
						arguments = { ... },
					})

					return dispatch(...)
				end
			end
		end

		self.gameProducer = gameProfile.CreateProducer(gameData)
		self.gameProducer:applyMiddleware(replicateMiddleware)
		self.isGameDataLoaded = true

		for _, data: { name: string, arguments: { any } } in pendingGameReplicationEvents do
			applyGameReplicationEvent(self, data)
		end

		table.clear(pendingGameReplicationEvents)
		self.gameDataLoadedSignal:Fire()

		return
	end

	ReplicatedStorage:WaitForChild("ReplicateStore").OnClientEvent
		:Connect(function(data: { name: string, arguments: { any } }): ()
			if type(data) ~= "table" then
				return
			end

			if not self.isPlayerDataLoaded then
				table.insert(pendingPlayerReplicationEvents, data)
				return
			end

			applyPlayerReplicationEvent(self, data)
		end)

	ReplicatedStorage:WaitForChild("ReplicateGameStore").OnClientEvent:Connect(function(data: { [string]: any }): ()
		if type(data) ~= "table" then
			return
		end

		if not self.isGameDataLoaded then
			table.insert(pendingGameReplicationEvents, data :: any)
			return
		end

		applyGameReplicationEvent(self, data :: any)
	end)

	Promise.all({
		Promise.defer(function(resolve: () -> ()): ()
			loadPlayerData()
			resolve()
		end),
		Promise.defer(function(resolve: () -> ()): ()
			loadGameData()
			resolve()
		end),
	}):expect()
end

return ClientData
