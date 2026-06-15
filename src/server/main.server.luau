--!nocheck
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local GetBridge = require(ReplicatedStorage.util.GetBridge)
local Logger = require(ReplicatedStorage.util.Logger)
local Promise = require(ReplicatedStorage.package.Promise)
local ServerInitConfig = require(ServerScriptService.server.serverConfig.ServerInitConfig)

local INIT_TIMEOUT_SECONDS = 5
local START_TIMEOUT_SECONDS = 10

local replicateToServer = Instance.new("RemoteFunction")
replicateToServer.Name = "_GetBridgeFunction"
replicateToServer.Parent = ReplicatedStorage

replicateToServer.OnServerInvoke = function(_player: Player, name: string): ()
	GetBridge(name)
end

local path = {}
path.controller = {}
path.module = {}
path.tag = {}
path.other = {}

local priorityControllers = {}
local regularControllers = {}
local tagModules = {}
local tagInstances = {}
local moduleMetadata = setmetatable({}, { __mode = "k" })
local controllersFullyLoaded = false
local controllersReadyEvent = Instance.new("BindableEvent")
local bootstrappedPlayers = {}

local function isDisabledByConfig(instance: Instance): boolean
	local current = instance
	while current and current ~= script.Parent do
		if table.find(ServerInitConfig, current.Name) then
			return true
		end
		current = current.Parent
	end

	return false
end

local function getTraceback(err: string): string
	return debug.traceback(err)
end

local function formatSeconds(seconds: number): string
	return string.format("%.3fs", math.max(seconds, 0))
end

local function getModuleName(required: unknown): string
	local metadata = moduleMetadata[required]
	if metadata and type(metadata.moduleName) == "string" and metadata.moduleName ~= "" then
		return metadata.moduleName
	end

	if type(required.name) == "string" and required.name ~= "" then
		return required.name
	end

	if type(required.type) == "string" and required.type ~= "" then
		return required.type
	end

	return "unknown"
end

local function getModulePath(required: unknown): string
	local metadata = moduleMetadata[required]
	if metadata and type(metadata.modulePath) == "string" and metadata.modulePath ~= "" then
		return metadata.modulePath
	end

	return getModuleName(required)
end

local function awaitControllersReady(): ()
	if controllersFullyLoaded then
		return
	end

	controllersReadyEvent.Event:Wait()
end

local function dispatchClass(callbackName: string, class: unknown, deferExecution: boolean, ...: any): ()
	local callback = class[callbackName]
	if type(callback) ~= "function" then
		return
	end

	local args = { ... }
	local schedule = if deferExecution then task.defer else task.spawn
	schedule(function(): ()
		local success: boolean, err: unknown = xpcall(function(): ()
			callback(class, unpack(args))
		end, getTraceback)

		if not success then
			Logger.warn(
				`ServerBootstrap[{callbackName}] failed for {getModuleName(class)} ({getModulePath(class)}): {tostring(
					err
				)}`
			)
		end
	end)
end

local function dispatchToRuntime(callbackName: string, deferExecution: boolean?, ...: any): ()
	local shouldDefer = deferExecution == true

	for _index: number, class: unknown in path.controller do
		dispatchClass(callbackName, class, shouldDefer, ...)
	end

	for _instance: Instance, classes: { [string]: unknown } in path.tag do
		for _tag: string, class: unknown in classes do
			dispatchClass(callbackName, class, shouldDefer, ...)
		end
	end
end

local function bootstrapPlayer(player: Player): ()
	if bootstrappedPlayers[player] then
		return
	end

	bootstrappedPlayers[player] = true
	dispatchToRuntime("PlayerAdded", false, player)

	local function bindCharacter(character: Model): ()
		dispatchToRuntime("CharacterAdded", false, player, character)

		local humanoid: Humanoid? = character:FindFirstChild("Humanoid") or character:WaitForChild("Humanoid", 10)
		if not humanoid then
			Logger.warn(`ServerBootstrap: missing Humanoid for {character:GetFullName()}`)
			return
		end

		humanoid.Died:Connect(function(): ()
			dispatchToRuntime("Died", false, player, character)
		end)
	end

	player.CharacterAdded:Connect(bindCharacter)

	player.CharacterAppearanceLoaded:Connect(function(character: Model): ()
		dispatchToRuntime("CharacterAppearanceLoaded", false, player, character)
	end)

	if player.Character then
		task.spawn(function(): ()
			bindCharacter(player.Character)

			local success: boolean, hasAppearanceLoaded: boolean = pcall(function(): boolean
				return player:HasAppearanceLoaded()
			end)

			if success and hasAppearanceLoaded then
				dispatchToRuntime("CharacterAppearanceLoaded", false, player, player.Character)
			end
		end)
	end
end

Players.PlayerAdded:Connect(function(player: Player): ()
	awaitControllersReady()
	bootstrapPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player: Player): ()
	if bootstrappedPlayers[player] then
		dispatchToRuntime("PlayerRemoving", false, player)
	end

	bootstrappedPlayers[player] = nil
end)

local folders: { Folder } = script.Parent:GetChildren()
table.insert(folders, ReplicatedStorage.shared.modules)

for _index: number, folder: Folder in folders do
	if table.find(ServerInitConfig, folder.Name) then
		continue
	end

	if not folder:IsA("Folder") then
		continue
	end

	for _moduleIndex: number, module: ModuleScript in folder:GetDescendants() do
		if not module:IsA("ModuleScript") then
			continue
		end

		if module.Name:lower():find("template") then
			continue
		end

		if isDisabledByConfig(module) then
			continue
		end

		local success: boolean, required: unknown = xpcall(function(): unknown
			return require(module)
		end, getTraceback)

		if not success then
			Logger.warn(`Failed to load module {module:GetFullName()}: {required}`)
			continue
		end

		if typeof(required) ~= "table" then
			continue
		end

		moduleMetadata[required] = {
			moduleName = module.Name,
			modulePath = module:GetFullName(),
		}

		local moduleType: string = required.type or "module"

		if moduleType == "controller" then
			if required.index ~= nil then
				table.insert(priorityControllers, required)
			else
				table.insert(regularControllers, required)
			end
		end

		if moduleType == "tag" then
			tagModules[module.Name] = required
		else
			path[moduleType][module.Name] = required
		end

		if moduleType == "other" then
			required.path = path
		elseif required.type then
			required.name = module.Name
		end
	end
end

table.sort(priorityControllers, function(a: unknown, b: unknown): boolean
	local leftIndex = tonumber(a.index) or math.huge
	local rightIndex = tonumber(b.index) or math.huge
	if leftIndex == rightIndex then
		return getModuleName(a) < getModuleName(b)
	end

	return leftIndex < rightIndex
end)

local function runControllerLifecyclePromise(required: unknown, phaseName: string, timeoutSeconds: number)
	local callback = required[phaseName]
	if type(callback) ~= "function" then
		return Promise.resolve({
			name = getModuleName(required),
			success = true,
			duration = 0,
			timedOut = false,
			skipped = true,
		})
	end

	return Promise.new(function(resolve): ()
		local controllerName = getModuleName(required)
		local controllerPath = getModulePath(required)
		local settled = false
		local timedOut = false

		task.spawn(function(): ()
			required.path = path

			local startedAt = os.clock()
			local success: boolean, err: unknown = xpcall(function(): ()
				callback(required)
			end, getTraceback)
			local duration = os.clock() - startedAt

			if timedOut then
				if success then
					Logger.warn(
						`ServerBootstrap[{phaseName}] late completion {controllerName} in {formatSeconds(duration)} ({controllerPath})`
					)
				else
					Logger.warn(
						`ServerBootstrap[{phaseName}] late failure {controllerName} in {formatSeconds(duration)} ({controllerPath}): {tostring(
							err
						)}`
					)
				end
				return
			end

			settled = true

			if success then
				Logger.print(`ServerBootstrap[{phaseName}] done {controllerName} in {formatSeconds(duration)}`)
			else
				Logger.warn(
					`ServerBootstrap[{phaseName}] failed {controllerName} in {formatSeconds(duration)} ({controllerPath}): {tostring(
						err
					)}`
				)
			end

			resolve({
				name = controllerName,
				success = success,
				duration = duration,
				timedOut = false,
				skipped = false,
				error = err,
			})
		end)

		task.delay(timeoutSeconds, function(): ()
			if settled then
				return
			end

			timedOut = true
			settled = true

			Logger.warn(
				`ServerBootstrap[{phaseName}] timeout {controllerName} after {formatSeconds(timeoutSeconds)} ({controllerPath}); continuing`
			)

			resolve({
				name = controllerName,
				success = false,
				duration = timeoutSeconds,
				timedOut = true,
				skipped = false,
				error = `timeout after {timeoutSeconds}s`,
			})
		end)
	end)
end

local function logLifecycleSummary(phaseName: string, results: { any }): ()
	local startedCount = 0
	local okCount = 0
	local failCount = 0
	local timeoutCount = 0
	local missingMethodCount = 0
	local slowestName = "n/a"
	local slowestDuration = 0

	for _, result in ipairs(results) do
		if result.skipped then
			missingMethodCount += 1
			continue
		end

		startedCount += 1
		if result.timedOut then
			timeoutCount += 1
		elseif result.success then
			okCount += 1
		else
			failCount += 1
		end

		if result.duration > slowestDuration then
			slowestDuration = result.duration
			slowestName = result.name
		end
	end

	Logger.print(
		`ServerBootstrap[{phaseName}] summary started={startedCount} ok={okCount} failed={failCount} timedOut={timeoutCount} no{phaseName}Method={missingMethodCount} slowest={slowestName} ({formatSeconds(
			slowestDuration
		)})`
	)
end

local function runControllerBarrier(controllers: { unknown }, phaseName: string, timeoutSeconds: number): { any }
	if #controllers == 0 then
		return {}
	end

	local total = #controllers
	local remaining = #controllers
	local promises = table.create(#controllers)
	for _, required in ipairs(controllers) do
		table.insert(
			promises,
			runControllerLifecyclePromise(required, phaseName, timeoutSeconds):andThen(function(result)
				remaining -= 1
				if not result.skipped then
					local completed = total - remaining
					Logger.print(
						`ServerBootstrap[{phaseName}] progress {result.name} {completed}/{total} in {formatSeconds(
							result.duration
						)}`
					)
				end
				return result
			end)
		)
	end

	local success: boolean, results: { any } = Promise.all(promises):await()
	if not success or type(results) ~= "table" then
		Logger.warn(`ServerBootstrap[{phaseName}] barrier failed unexpectedly`)
		return {}
	end

	logLifecycleSummary(phaseName, results)
	return results
end

local function runControllerSequence(controllers: { unknown }, phaseName: string, timeoutSeconds: number): { any }
	if #controllers == 0 then
		return {}
	end

	local total = #controllers
	local remaining = #controllers
	local results = table.create(#controllers)
	for _, required in ipairs(controllers) do
		local success: boolean, result = runControllerLifecyclePromise(required, phaseName, timeoutSeconds):await()
		if success and result then
			remaining -= 1
			if not result.skipped then
				local completed = total - remaining
				Logger.print(
					`ServerBootstrap[{phaseName}] progress {result.name} {completed}/{total} in {formatSeconds(
						result.duration
					)}`
				)
			end
			table.insert(results, result)
		end
	end

	logLifecycleSummary(phaseName, results)
	return results
end

local function InitTag(required: unknown): ()
	local tag: string = required.tag
	if not tag then
		Logger.warn("Tag not specified for tag module:", getModuleName(required))
		return
	end

	local new: ((Instance, unknown?) -> unknown)? = required.new
	if not new then
		Logger.warn("New function not specified for tag module:", getModuleName(required))
		return
	end

	local PlayerAdded: ((unknown, Player) -> unknown)? = required.PlayerAdded
	required.tagclasses = {}

	local function addInstance(instance: Instance): ()
		local class: unknown = new(instance, path)
		if not class then
			return
		end

		class.path = path

		if not tagInstances[instance] then
			tagInstances[instance] = {}
		end
		tagInstances[instance][tag] = class

		if not path.tag[instance] then
			path.tag[instance] = {}
		end
		path.tag[instance][tag] = class

		if not required.tagclass then
			required.tagclass = class
		end

		table.insert(required.tagclasses, class)

		if PlayerAdded then
			for _index: number, player: Player in Players:GetPlayers() do
				task.spawn(PlayerAdded, required, player)
			end
		end
	end

	local function removeInstance(instance: Instance): ()
		local class: unknown = tagInstances[instance] and tagInstances[instance][tag]

		table.remove(required.tagclasses, table.find(required.tagclasses, class))

		if required.tagclass == class then
			required.tagclass = select(2, next(required.tagclasses))
		end

		if class and class.Destroy then
			class:Destroy(instance)
		end

		if tagInstances[instance] then
			tagInstances[instance][tag] = nil
		end

		if path.tag[instance] then
			path.tag[instance][tag] = nil
			if next(path.tag[instance]) == nil then
				path.tag[instance] = nil
			end
		end
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(addInstance)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removeInstance)

	for _index: number, instance: Instance in CollectionService:GetTagged(tag) do
		task.spawn(addInstance, instance)
	end
end

runControllerSequence(priorityControllers, "Init", INIT_TIMEOUT_SECONDS)
runControllerBarrier(regularControllers, "Init", INIT_TIMEOUT_SECONDS)

for _index: number, required: unknown in tagModules do
	task.spawn(function(): ()
		local startedAt = os.clock()
		local success: boolean, err: unknown = xpcall(function(): ()
			InitTag(required)
		end, getTraceback)
		local duration = os.clock() - startedAt

		if success then
			Logger.print(`ServerBootstrap[TagInit] done {getModuleName(required)} in {formatSeconds(duration)}`)
		else
			Logger.warn(
				`ServerBootstrap[TagInit] failed {getModuleName(required)} in {formatSeconds(duration)}: {tostring(err)}`
			)
		end
	end)
end

runControllerSequence(priorityControllers, "Start", START_TIMEOUT_SECONDS)
runControllerBarrier(regularControllers, "Start", START_TIMEOUT_SECONDS)

controllersFullyLoaded = true
controllersReadyEvent:Fire()

for _index: number, player: Player in Players:GetPlayers() do
	task.spawn(bootstrapPlayer, player)
end

RunService.Heartbeat:Connect(function(delta: number): ()
	dispatchToRuntime("Physics", true, delta)
end)

RunService.PreSimulation:Connect(function(delta: number): ()
	dispatchToRuntime("Stepped", true, delta)
end)
