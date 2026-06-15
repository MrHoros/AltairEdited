--!nocheck
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientInitConfig = require(ReplicatedStorage.client.clientConfig.ClientInitConfig)
local LocalPlayer = require(ReplicatedStorage.util.LocalPlayer)
local Logger = require(ReplicatedStorage.util.Logger)
local Maid = require(ReplicatedStorage.package.Maid)
local OpenGui = require(ReplicatedStorage.util.OpenGui)
local Promise = require(ReplicatedStorage.package.Promise)

local sharedFolder: Folder = ReplicatedStorage:WaitForChild("shared") :: Folder
sharedFolder:WaitForChild("types")
sharedFolder:WaitForChild("reflex")
sharedFolder:WaitForChild("config")
sharedFolder:WaitForChild("modules")
sharedFolder:WaitForChild("model")

local LOADING_SCREEN_NAME: string = "LoadingScreen"
local LOADING_SCREEN_INIT_FORMAT: string = "Initializing controllers %d/%d"
local LOADING_SCREEN_START_FORMAT: string = "Starting systems %d/%d"
local DEFAULT_LOADING_CONTROLLER_TOTAL: number = 20
local LOADING_ATTRIBUTE_CLIENT_INIT_READY: string = "ClientInitReady"
local LOADING_ATTRIBUTE_CLIENT_START_READY: string = "ClientStartReady"
local LOADING_ATTRIBUTE_PHASE: string = "LoadingPhase"

local path = {}
path.controller = {}
path.module = {}
path.local_tag = {}
path.tag = {}
path.other = {}

local moduleTags = {}
local moduleTagsLocal = {}
local tagInstances = {}
local loadFirst = {}
local loadFirstEntries = {}
local load = {}
local loadedControllerCount: number = 0
local startedControllerCount: number = 0
local totalControllerCount: number = 0
local loadingScreenGui: ScreenGui? = nil
local loadingScreenBar: Frame? = nil
local loadingScreenLoadedPercent: TextLabel? = nil
local loadingScreenText: TextLabel? = nil
local clientBootstrapReady: boolean = false
local loadingScreenAttributes: { [string]: any } = {}
local loadingScreenPhase: string = "Initializing"

local function removeTagClass(instance: Instance, tag: string, class: unknown, classes: { unknown }): ()
	local classIndex: number? = table.find(classes, class)
	if classIndex then
		table.remove(classes, classIndex)
	end

	if tagInstances[instance] then
		tagInstances[instance][tag] = nil

		if next(tagInstances[instance]) == nil then
			tagInstances[instance] = nil
		end
	end
end

local function getVisibleTotalControllerCount(): number
	return if totalControllerCount > 0 then totalControllerCount else DEFAULT_LOADING_CONTROLLER_TOTAL
end

local function getLoadingScreenGui(): ScreenGui?
	if loadingScreenGui and loadingScreenGui.Parent then
		return loadingScreenGui
	end

	local playerGui: PlayerGui? = LocalPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
	if not playerGui then
		return
	end

	local gui: ScreenGui? = playerGui:FindFirstChild(LOADING_SCREEN_NAME) :: ScreenGui?
	if gui and gui:IsA("ScreenGui") then
		return gui
	end

	return
end

local function setLoadingScreenAttribute(attributeName: string, value: any): ()
	loadingScreenAttributes[attributeName] = value

	local gui: ScreenGui? = getLoadingScreenGui()
	if gui then
		gui:SetAttribute(attributeName, value)
	end
end

local function applyLoadingScreenAttributes(): ()
	local gui: ScreenGui? = getLoadingScreenGui()
	if not gui then
		return
	end

	for attributeName: string, value: any in loadingScreenAttributes do
		gui:SetAttribute(attributeName, value)
	end
end

local function publishLoadingScreenProgress(isReady: boolean?): ()
	if isReady == true then
		clientBootstrapReady = true
	end

	local total: number = getVisibleTotalControllerCount()
	local progress: number = if total > 0 then (loadedControllerCount + startedControllerCount) / (total * 2) else 0
	progress = math.clamp(progress, 0, 1)

	if isReady == true then
		progress = 1
	end

	if loadingScreenBar and loadingScreenBar.Parent then
		loadingScreenBar.Size = UDim2.fromScale(progress, 1)
		loadingScreenBar.Visible = progress > 0
	end

	if loadingScreenLoadedPercent and loadingScreenLoadedPercent.Parent then
		loadingScreenLoadedPercent.Text = `{math.floor(progress * 100)}%`
	end

	if loadingScreenText and loadingScreenText.Parent then
		if isReady == true then
			loadingScreenText.Text = "Ready"
		elseif loadingScreenPhase == "Starting" then
			loadingScreenText.Text = string.format(LOADING_SCREEN_START_FORMAT, startedControllerCount, total)
		else
			loadingScreenText.Text = string.format(LOADING_SCREEN_INIT_FORMAT, loadedControllerCount, total)
		end
	end
end

local function markControllerLoaded(): ()
	if loadedControllerCount >= totalControllerCount then
		return
	end

	loadedControllerCount += 1
	publishLoadingScreenProgress()
end

local function markControllerStarted(): ()
	if startedControllerCount >= totalControllerCount then
		return
	end

	startedControllerCount += 1
	publishLoadingScreenProgress()
end

task.spawn(function(): ()
	local playerGui: PlayerGui? = LocalPlayer:FindFirstChild("PlayerGui") :: PlayerGui?
		or LocalPlayer:WaitForChild("PlayerGui", 10) :: PlayerGui?
	if not playerGui then
		return
	end

	local gui: ScreenGui? = playerGui:FindFirstChild(LOADING_SCREEN_NAME) :: ScreenGui?
		or playerGui:WaitForChild(LOADING_SCREEN_NAME, 10) :: ScreenGui?
	if not gui or not gui:IsA("ScreenGui") then
		return
	end

	loadingScreenGui = gui
	applyLoadingScreenAttributes()

	local core: CanvasGroup? = gui:FindFirstChild("Core") :: CanvasGroup?
	if not core or not core:IsA("CanvasGroup") then
		return
	end

	local loadingText: TextLabel? = core:FindFirstChild("LoadingNow") :: TextLabel?
	if not loadingText or not loadingText:IsA("TextLabel") then
		return
	end

	local progressFrame: Frame? = core:FindFirstChild("Progress") :: Frame?
	if not progressFrame or not progressFrame:IsA("Frame") then
		return
	end

	local progressBar: Frame? = progressFrame:FindFirstChild("Bar") :: Frame?
	if not progressBar or not progressBar:IsA("Frame") then
		return
	end

	local loadedPercent: TextLabel? = progressFrame:FindFirstChild("LoadedPercent") :: TextLabel?
	if not loadedPercent or not loadedPercent:IsA("TextLabel") then
		return
	end

	loadingScreenBar = progressBar
	loadingScreenLoadedPercent = loadedPercent
	loadingScreenText = loadingText
	publishLoadingScreenProgress(clientBootstrapReady)
end)

local folders: { Folder } = ReplicatedStorage:WaitForChild("client"):GetChildren()
table.insert(folders, sharedFolder:WaitForChild("modules"))

for _index: number, folder: Folder in folders do
	if table.find(ClientInitConfig, folder.Name) then
		continue
	end

	if not folder:IsA("Folder") then
		continue
	end

	for _index: number, module: ModuleScript in folder:GetDescendants() do
		if not module:IsA("ModuleScript") then
			continue
		end

		local moduleName: string = module.Name
		if moduleName:lower():find("template") then
			continue
		end

		local success: boolean, required: unknown = xpcall(function(): ()
			return require(module)
		end, function(err: string): string
			return debug.traceback(err)
		end)

		if not success then
			Logger.warn(`Failed to load module {module:GetFullName()}: {required}`)
			continue
		end

		if typeof(required) ~= "table" then
			continue
		end

		local moduleType: string = required.type or "module"

		if moduleType == "controller" then
			local rawIndex: unknown = required.index
			if type(rawIndex) == "number" then
				table.insert(loadFirstEntries, {
					index = rawIndex,
					moduleName = moduleName,
					required = required,
				})
			else
				table.insert(load, required)
			end
		end

		if moduleType == "tag" then
			moduleTags[module.Name] = required
		elseif moduleType == "local_tag" then
			moduleTagsLocal[module.Name] = required
		else
			path[moduleType][module.Name] = required
		end

		if moduleType == "other" then
			required.path = path
		elseif required.type then
			required.name = moduleName
		end
	end
end

table.sort(loadFirstEntries, function(a: any, b: any): boolean
	if a.index == b.index then
		return tostring(a.moduleName) < tostring(b.moduleName)
	end

	return a.index < b.index
end)

for index: number = 1, #loadFirstEntries do
	local entry: any = loadFirstEntries[index]
	local required: unknown = entry.required

	table.insert(loadFirst, required)
end

totalControllerCount = #loadFirst + #load
setLoadingScreenAttribute(LOADING_ATTRIBUTE_PHASE, loadingScreenPhase)
publishLoadingScreenProgress(false)

local function InitController(required: unknown): ()
	required.path = path

	local Init: ((unknown?) -> unknown?)? = required.Init
	if Init then
		local success: boolean, err: unknown = xpcall(function(): ()
			Init(required)
		end, function(err2: string): string
			return debug.traceback(err2)
		end)

		if not success then
			Logger.warn(`Failed to initialize controller {required.type or "unknown"}: {err}`)
		end
	end
end

local function InitControllerAsync(required: unknown, context: string): Promise.Promise
	local regularDelaySeconds: number = 5
	local delay: number = context == "regular" and regularDelaySeconds or 2

	return Promise.new(function(resolve: () -> ()): ()
		local warningPromise = Promise.delay(delay):andThen(function(): ()
			Logger.warn(
				`Initialization of {context} controller {required.type or "unknown"} `
					.. `({required.name or "unknown"}) exceeded {delay}s`
			)
		end)

		task.spawn(function(): ()
			InitController(required)
			warningPromise:cancel()
			resolve()
		end)
	end)
end

local function StartController(required: unknown): ()
	local Start: ((unknown?) -> unknown?)? = required.Start
	if Start then
		local success: boolean, err: unknown = xpcall(function(): ()
			Start(required)
		end, function(err2: string): string
			return debug.traceback(err2)
		end)

		if not success then
			Logger.warn(`Failed to start controller {required.type or "unknown"}: {err}`)
		end
	end
end

local function InitTag(required: unknown): ()
	local tag: string = required.tag
	if not tag then
		Logger.warn("Tag not specified for required module")
		return
	end

	local new: ((Instance) -> unknown)? = required.new
	if not new then
		Logger.warn("New function not specified for tag module:", required.name)
		return
	end

	required.tagclasses = {}

	local function addInstance(instance: Instance): ()
		--print(table.concat(instance:GetTags(), ", "), " | ", instance:GetFullName())

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
	end

	local function removeInstance(instance: Instance): ()
		local class: unknown = tagInstances[instance] and tagInstances[instance][tag]

		removeTagClass(instance, tag, class, required.tagclasses)

		if required.tagclass == class then
			required.tagclass = select(2, next(required.tagclasses))
		end

		if class and class.Destroy then
			class:Destroy(instance)
			class = nil
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

local function InitLocalTag(required: unknown): ()
	local tag: string = required.tag
	if not tag then
		Logger.warn("Tag not specified for local tag module:", required.name)
		return
	end

	local new: ((Instance) -> unknown)? = required.new
	if not new then
		Logger.warn("New function not specified for local tag module:", required.name)
		return
	end

	required.tagclasses = {}

	local function addInstance(instance: Instance): ()
		if not LocalPlayer:IsAncestorOf(instance) then
			if not LocalPlayer.Character or not LocalPlayer.Character:IsAncestorOf(instance) then
				return
			end
		end

		local class: unknown = new(instance, path)
		if not class then
			return
		end

		class.path = path

		if not tagInstances[instance] then
			tagInstances[instance] = {}
		end
		tagInstances[instance][tag] = class

		path.local_tag[instance] = class

		if not required.tagclass then
			required.tagclass = class
		end

		table.insert(required.tagclasses, class)

		if class.closeButtons then
			for _index: number, button: GuiButton in class.closeButtons or {} do
				if not class.closeButtonsMaid then
					class.closeButtonsMaid = Maid.new()
				end

				class.closeButtonsMaid:GiveTask(button.MouseButton1Down:Connect(function(): ()
					if class.Close then
						class:Close()
					else
						OpenGui:Close(required)
					end
				end))
			end
		end

		if class.openButtons then
			if not class.openButtonsMaid then
				class.openButtonsMaid = Maid.new()
			end

			for _index: number, button: GuiButton in class.openButtons or {} do
				class.openButtonsMaid:GiveTask(button.MouseButton1Down:Connect(function(): ()
					if class.Open then
						class:Open()
					else
						OpenGui:Open(required)
					end
				end))
			end
		end

		if class.toggleButtons then
			if not class.toggleButtonsMaid then
				class.toggleButtonsMaid = Maid.new()
			end

			for _index: number, button: GuiButton in class.toggleButtons or {} do
				class.toggleButtonsMaid:GiveTask(button.MouseButton1Down:Connect(function(): ()
					if class.Toggle then
						class:Toggle()
					else
						OpenGui:Toggle(required)
					end
				end))
			end
		end
	end

	local function removeInstance(instance: Instance): ()
		local class: unknown = tagInstances[instance] and tagInstances[instance][tag]

		removeTagClass(instance, tag, class, required.tagclasses)

		if required.tagclass == class then
			required.tagclass = select(2, next(required.tagclasses))
		end

		if class then
			if class.closeButtonsMaid and class.closeButtonsMaid.DoCleaning then
				class.closeButtonsMaid:DoCleaning()
			end

			if class.openButtonsMaid and class.openButtonsMaid.DoCleaning then
				class.openButtonsMaid:DoCleaning()
			end

			if class.toggleButtonsMaid and class.toggleButtonsMaid.DoCleaning then
				class.toggleButtonsMaid:DoCleaning()
			end

			if class.Destroy then
				class:Destroy(instance)
				class = nil
			end
		end

		path.local_tag[instance] = nil
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(addInstance)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removeInstance)

	for _index: number, instance: Instance in CollectionService:GetTagged(tag) do
		task.spawn(addInstance, instance)
	end
end

for index: number = 1, #loadFirst do
	local required: unknown = loadFirst[index]
	local success: boolean, err: unknown = xpcall(function(): ()
		InitControllerAsync(required, "priority"):expect()
	end, function(err2: string): string
		return debug.traceback(err2)
	end)

	if not success then
		Logger.warn(`Failed to initialize priority controller of type {required.type or "unknown"}: {err}`)
	end

	markControllerLoaded()
end

for _index: number, required: unknown in load do
	local success: boolean, err: unknown = xpcall(function(): ()
		InitControllerAsync(required, "regular"):expect()
	end, function(err2: string): string
		return debug.traceback(err2)
	end)

	if not success then
		Logger.warn(`Failed to initialize controller of type {required.type or "unknown"}: {err}`)
	end

	markControllerLoaded()
end

setLoadingScreenAttribute(LOADING_ATTRIBUTE_CLIENT_INIT_READY, true)
loadingScreenPhase = "Starting"
setLoadingScreenAttribute(LOADING_ATTRIBUTE_PHASE, loadingScreenPhase)
publishLoadingScreenProgress(false)

for _index: number, required: unknown in moduleTags do
	task.spawn(InitTag, required)
end

for _index: number, required: unknown in moduleTagsLocal do
	task.spawn(InitLocalTag, required)
end

for index: number = 1, #loadFirst do
	local required: unknown = loadFirst[index]
	local success: boolean, err: unknown = xpcall(function(): ()
		StartController(required)
	end, function(err2: string): string
		return debug.traceback(err2)
	end)

	if not success then
		Logger.warn(`Failed to start priority controller of type {required.type or "unknown"}: {err}`)
	end

	markControllerStarted()
end

for _index: number, required: unknown in load do
	local success: boolean, err: unknown = xpcall(function(): ()
		StartController(required)
	end, function(err2: string): string
		return debug.traceback(err2)
	end)

	if not success then
		Logger.warn(`Failed to start controller {required.type or "unknown"}: {err}`)
	end

	markControllerStarted()
end

setLoadingScreenAttribute(LOADING_ATTRIBUTE_CLIENT_START_READY, true)
publishLoadingScreenProgress(true)

Players.PlayerRemoving:Connect(function(player: Player): ()
	for _index: number, class: unknown in path.controller do
		task.spawn(function(): ()
			if class.PlayerRemoving then
				class:PlayerRemoving(player)
			end
		end)
	end

	for _instance: Instance, classes: { unknown } in path.tag do
		for _index: number, class: unknown in classes do
			task.spawn(function(): ()
				if class.PlayerRemoving then
					class:PlayerRemoving(player)
				end
			end)
		end
	end

	for _instance: Instance, class: unknown in path.local_tag do
		task.spawn(function(): ()
			if class and class.PlayerRemoving then
				class:PlayerRemoving(player)
			end
		end)
	end
end)

Players.PlayerAdded:Connect(function(player: Player): ()
	for _index: number, class: unknown in path.controller do
		task.spawn(function(): ()
			if class.PlayerAdded then
				class:PlayerAdded(player)
			end
		end)
	end

	for _instance: Instance, classes: { unknown } in path.tag do
		for _index: number, class: unknown in classes do
			task.spawn(function(): ()
				if class.PlayerAdded then
					class:PlayerAdded(player)
				end
			end)
		end
	end

	for _instance: Instance, class: unknown in path.local_tag do
		task.spawn(function(): ()
			if class and class.PlayerAdded then
				class:PlayerAdded(player)
			end
		end)
	end

	player.CharacterAdded:Connect(function(character: Model): ()
		for _index: number, class: unknown in path.controller do
			task.spawn(function(): ()
				if class.AnyCharacterAdded then
					class:AnyCharacterAdded(player, character)
				end
			end)
		end

		for _instance: Instance, classes: { unknown } in path.tag do
			for _index: number, class: unknown in classes do
				task.defer(function(): ()
					if class.CharacterAdded then
						class:CharacterAdded(player, character)
					end
				end)
			end
		end

		for _instance: Instance, class: unknown in path.local_tag do
			task.defer(function(): ()
				if class and class.CharacterAdded then
					class:CharacterAdded(player, character)
				end
			end)
		end

		local humanoid: Humanoid = character:WaitForChild("Humanoid")

		humanoid.Died:Connect(function(): ()
			for _index: number, class: unknown in path.controller do
				if class.AnyDied then
					class:AnyDied(player, character)
				end
			end

			for _instance: Instance, classes: { unknown } in path.tag do
				for _index: number, class: unknown in classes do
					task.defer(function(): ()
						if class.AnyDied then
							class:AnyDied(player, character)
						end
					end)
				end
			end

			for _instance: Instance, class: unknown in path.local_tag do
				task.defer(function(): ()
					if class and class.AnyDied then
						class:AnyDied(player, character)
					end
				end)
			end
		end)
	end)

	player.CharacterAppearanceLoaded:Connect(function(character: Model): ()
		for _index: number, class: unknown in path.controller do
			task.spawn(function(): ()
				if class.AnyCharacterAppearanceLoaded then
					class:AnyCharacterAppearanceLoaded(player, character)
				end
			end)
		end

		for _instance: Instance, classes: { unknown } in path.tag do
			for _index: number, class: unknown in classes do
				task.defer(function(): ()
					if class.AnyCharacterAppearanceLoaded then
						class:AnyCharacterAppearanceLoaded(player, character)
					end
				end)
			end
		end

		for _instance: Instance, class: unknown in path.local_tag do
			task.defer(function(): ()
				if class and class.AnyCharacterAppearanceLoaded then
					class:AnyCharacterAppearanceLoaded(player, character)
				end
			end)
		end
	end)
end)

LocalPlayer.CharacterAdded:Connect(function(character: Model): ()
	for _index: number, class: unknown in path.controller do
		task.spawn(function(): ()
			if class.CharacterAdded then
				class:CharacterAdded(character)
			end
		end)
	end

	for _instance: Instance, classes: { unknown } in path.tag do
		for _index: number, class: unknown in classes do
			task.defer(function(): ()
				if class.CharacterAdded then
					class:CharacterAdded(character)
				end
			end)
		end
	end

	for _instance: Instance, class: unknown in path.local_tag do
		task.defer(function(): ()
			if class and class.CharacterAdded then
				class:CharacterAdded(character)
			end
		end)
	end

	local humanoid: Humanoid = character:WaitForChild("Humanoid")

	humanoid.Died:Connect(function(): ()
		for _index: number, class: unknown in path.controller do
			task.spawn(function(): ()
				if class.Died then
					class:Died(character)
				end
			end)
		end

		for _instance: Instance, classes: { unknown } in path.tag do
			for _index: number, class: unknown in classes do
				task.defer(function(): ()
					if class.Died then
						class:Died(character)
					end
				end)
			end
		end

		for _instance: Instance, class: unknown in path.local_tag do
			task.defer(function(): ()
				if class and class.Died then
					class:Died(character)
				end
			end)
		end
	end)
end)

LocalPlayer.CharacterAppearanceLoaded:Connect(function(character: Model): ()
	for _index: number, class: unknown in path.controller do
		task.spawn(function(): ()
			if class.CharacterAppearanceLoaded then
				class:CharacterAppearanceLoaded(character)
			end
		end)
	end

	for _instance: Instance, classes: { unknown } in path.tag do
		for _index: number, class: unknown in classes do
			task.defer(function(): ()
				if class.CharacterAppearanceLoaded then
					class:CharacterAppearanceLoaded(character)
				end
			end)
		end
	end

	for _instance: Instance, class: unknown in path.local_tag do
		task.defer(function(): ()
			if class and class.CharacterAppearanceLoaded then
				class:CharacterAppearanceLoaded(character)
			end
		end)
	end
end)

RunService.Heartbeat:Connect(function(delta: number): ()
	for _index: number, class: unknown in path.controller do
		task.defer(function(): ()
			if class.Physics then
				class:Physics(delta)
			end
		end)
	end
	for _instance: Instance, classes: { unknown } in path.tag do
		for _index: number, class: unknown in classes do
			task.defer(function(): ()
				if class.Physics then
					class:Physics(delta)
				end
			end)
		end
	end

	for _instance: Instance, class: unknown in path.local_tag do
		task.defer(function(): ()
			if class and class.Physics then
				class:Physics(delta)
			end
		end)
	end
end)

RunService.PreSimulation:Connect(function(delta: number): ()
	for _index: number, class: unknown in path.controller do
		task.defer(function(): ()
			if class.Stepped then
				class:Stepped(delta)
			end
		end)
	end

	for _instance: Instance, classes: { unknown } in path.tag do
		for _index: number, class: unknown in classes do
			task.defer(function(): ()
				if class.Stepped then
					class:Stepped(delta)
				end
			end)
		end
	end

	for _instance: Instance, class: unknown in path.local_tag do
		task.defer(function(): ()
			if class and class.Stepped then
				class:Stepped(delta)
			end
		end)
	end
end)

RunService.PreRender:Connect(function(delta: number): ()
	for _index: number, class: unknown in path.controller do
		task.defer(function(): ()
			if class.Render then
				class:Render(delta)
			end
		end)
	end

	for _instance: Instance, classes: { unknown } in path.tag do
		for _index: number, class: unknown in classes do
			task.defer(function(): ()
				if class.Render then
					class:Render(delta)
				end
			end)
		end
	end

	for _instance: Instance, class: unknown in path.local_tag do
		task.defer(function(): ()
			if class and class.Render then
				class:Render(delta)
			end
		end)
	end
end)

for _index: number, ui: ScreenGui in LocalPlayer.PlayerGui:GetChildren() do
	if ui:IsA("ScreenGui") and not ui:GetAttribute("SkipResetOnSpawn") then
		ui.ResetOnSpawn = false
	end
end

LocalPlayer.PlayerGui.ChildAdded:Connect(function(ui: Instance): ()
	if ui:IsA("ScreenGui") and not ui:GetAttribute("SkipResetOnSpawn") then
		ui.ResetOnSpawn = false
	end
end)
