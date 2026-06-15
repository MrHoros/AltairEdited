--!nolint LocalUnused
--selene: allow(unused_variable)

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local BootstrapConfig = require(ReplicatedFirst:WaitForChild("BootstrapConfig"))
local ClientData = require(ReplicatedStorage:WaitForChild("client"):WaitForChild("modules"):WaitForChild("ClientData"))
local GetBridge = require(ReplicatedStorage.util.GetBridge)
local Promise = require(ReplicatedStorage.package.Promise)
local SetCharacterControlsEnabled = require(ReplicatedStorage.util.SetCharacterControlsEnabled)

local LocalPlayer = Players.LocalPlayer

local LOADING_ATTRIBUTE_CLIENT_INIT_READY: string = "ClientInitReady"
local LOADING_ATTRIBUTE_CLIENT_START_READY: string = "ClientStartReady"
local LOADING_ATTRIBUTE_DATA_READY: string = "DataReady"
local LOADING_ATTRIBUTE_SKIP_REQUESTED: string = "SkipRequested"
local LOADING_SCREEN_NAME: string = "LoadingScreen"
local LOADING_SCREEN_SOURCE_NAME: string = "loadingScreen"
local LOADING_SCREEN_ENABLED: boolean = BootstrapConfig.enableLoadingScreen ~= false
local MAX_CORE_GUI_ATTEMPTS: number = 200
local PRELOAD_BATCH_SIZE: number = 8
local RETRY_DELAY_SECONDS: number = 0.05
local READY_TO_SKIP_TEXT: string = "Click to skip"
local WAIT_WARNING_SECONDS: number = 15

if LOADING_SCREEN_ENABLED then
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end

local function setCoreGuiEnabled(enabled: boolean): boolean
	return xpcall(function(): ()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, enabled)
	end, warn)
end

local function setBackpackEnabled(enabled: boolean): boolean
	return xpcall(function(): ()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled)
	end, warn)
end

local function applyCoreGuiState(enabled: boolean): ()
	for _attempt: number = 1, MAX_CORE_GUI_ATTEMPTS do
		if setCoreGuiEnabled(enabled) then
			if enabled then
				setBackpackEnabled(false)
			end

			return
		end

		task.wait(RETRY_DELAY_SECONDS)
	end
end

local function getOrCloneLoadingScreen(playerGui: PlayerGui): ScreenGui?
	if not LOADING_SCREEN_ENABLED then
		return
	end

	local existing: ScreenGui? = playerGui:FindFirstChild(LOADING_SCREEN_NAME) :: ScreenGui?
	if existing then
		return existing
	end

	local template: ScreenGui? = ReplicatedFirst:FindFirstChild(LOADING_SCREEN_SOURCE_NAME) :: ScreenGui?
		or ReplicatedFirst:FindFirstChild(LOADING_SCREEN_NAME) :: ScreenGui?
	if not template then
		return
	end

	local clone: ScreenGui = template:Clone()
	clone.Name = LOADING_SCREEN_NAME
	clone.DisplayOrder = 10_000
	clone.IgnoreGuiInset = true
	clone.ResetOnSpawn = false
	clone.Parent = playerGui

	return clone
end

local function getCore(loadingScreen: ScreenGui): CanvasGroup
	local core: CanvasGroup = loadingScreen:WaitForChild("Core") :: CanvasGroup
	if not core:IsA("CanvasGroup") then
		error("LoadingScreen.Core must be a CanvasGroup")
	end

	return core
end

local function getLoadingText(loadingScreen: ScreenGui): TextLabel
	local core: CanvasGroup = getCore(loadingScreen)
	local loadingTextLabel: TextLabel = core:WaitForChild("LoadingNow") :: TextLabel
	if not loadingTextLabel:IsA("TextLabel") then
		error("LoadingScreen.Core.LoadingNow must be a TextLabel")
	end

	return loadingTextLabel
end

local function getProgressBar(loadingScreen: ScreenGui): Frame
	local core: CanvasGroup = getCore(loadingScreen)
	local progressFrame: Frame = core:WaitForChild("Progress") :: Frame
	local progressBar: Frame = progressFrame:WaitForChild("Bar") :: Frame
	if not progressBar:IsA("Frame") then
		error("LoadingScreen.Core.Progress.Bar must be a Frame")
	end

	return progressBar
end

local function getLoadedPercent(loadingScreen: ScreenGui): TextLabel
	local core: CanvasGroup = getCore(loadingScreen)
	local progressFrame: Frame = core:WaitForChild("Progress") :: Frame
	local loadedPercent: TextLabel = progressFrame:WaitForChild("LoadedPercent") :: TextLabel
	if not loadedPercent:IsA("TextLabel") then
		error("LoadingScreen.Core.Progress.LoadedPercent must be a TextLabel")
	end

	return loadedPercent
end

local function getSkipButton(loadingScreen: ScreenGui): GuiButton
	local core: CanvasGroup = getCore(loadingScreen)
	local skipButton: GuiButton = core:WaitForChild("Skip") :: GuiButton
	if not skipButton:IsA("GuiButton") then
		error("LoadingScreen.Core.Skip must be a GuiButton")
	end

	return skipButton
end

local function setSkipButtonVisible(skipButton: GuiButton, isVisible: boolean): ()
	if skipButton:IsA("TextButton") then
		skipButton.Text = READY_TO_SKIP_TEXT
	end

	skipButton.Visible = isVisible
end

local function setLoadingProgress(loadingScreen: ScreenGui, statusText: string, progress: number): ()
	local progressBar: Frame = getProgressBar(loadingScreen)
	local loadedPercent: TextLabel = getLoadedPercent(loadingScreen)

	progress = math.clamp(progress, 0, 1)
	getLoadingText(loadingScreen).Text = statusText
	loadedPercent.Text = `{math.floor(progress * 100)}%`
	progressBar.Size = UDim2.fromScale(progress, 1)
	progressBar.Visible = progress > 0
end

local function preloadPlayerGuiImages(playerGui: PlayerGui): ()
	local descendants: { Instance } = playerGui:GetDescendants()
	local total: number = #descendants
	if total == 0 then
		return
	end

	for startIndex: number = 1, total, PRELOAD_BATCH_SIZE do
		local batch: { Instance } = {}

		for offset: number = 0, PRELOAD_BATCH_SIZE - 1 do
			local item: Instance? = descendants[startIndex + offset]
			if item and (item:IsA("ImageLabel") or item:IsA("ImageButton")) then
				batch[#batch + 1] = item
			end
		end

		if #batch > 0 then
			xpcall(function(): ()
				ContentProvider:PreloadAsync(batch)
			end, warn)
		end

		task.wait()
	end
end

local function waitForLoadingAttribute(loadingScreen: ScreenGui, attributeName: string): Promise.Promise
	if loadingScreen:GetAttribute(attributeName) == true then
		return Promise.resolve()
	end

	return Promise.fromEvent(loadingScreen:GetAttributeChangedSignal(attributeName), function(): boolean
		return loadingScreen:GetAttribute(attributeName) == true
	end)
end

local function warnIfStillWaiting(label: string, isWaiting: () -> boolean): ()
	task.delay(WAIT_WARNING_SECONDS, function(): ()
		if isWaiting() then
			warn(`LoadingScreen: still waiting for {label}`)
		end
	end)
end

local function waitForPlayerData(loadingScreen: ScreenGui?): ()
	warnIfStillWaiting("player data", function(): boolean
		return not ClientData.isPlayerDataLoaded
	end)

	ClientData:GetPlayerProducerAsync():expect()

	if loadingScreen then
		loadingScreen:SetAttribute(LOADING_ATTRIBUTE_DATA_READY, true)
	end
end

local function waitForClientInit(loadingScreen: ScreenGui): ()
	warnIfStillWaiting("client init", function(): boolean
		return loadingScreen.Parent ~= nil and loadingScreen:GetAttribute(LOADING_ATTRIBUTE_CLIENT_INIT_READY) ~= true
	end)

	waitForLoadingAttribute(loadingScreen, LOADING_ATTRIBUTE_CLIENT_INIT_READY):expect()
end

local function waitForStartOrSkip(loadingScreen: ScreenGui, skipButton: GuiButton): ()
	setSkipButtonVisible(skipButton, true)

	local startReadyPromise: Promise.Promise =
		waitForLoadingAttribute(loadingScreen, LOADING_ATTRIBUTE_CLIENT_START_READY)
	local skipPromise: Promise.Promise = Promise.fromEvent(skipButton.Activated):andThen(function(): ()
		loadingScreen:SetAttribute(LOADING_ATTRIBUTE_SKIP_REQUESTED, true)
	end)

	Promise.race({
		startReadyPromise,
		skipPromise,
	}):expect()
end

local function finishLoading(loadingScreen: ScreenGui?): ()
	GetBridge("PlayerReady"):Fire()
	SetCharacterControlsEnabled(true)
	applyCoreGuiState(true)

	if loadingScreen then
		loadingScreen:Destroy()
	end
end

local playerGui: PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local loadingScreen: ScreenGui? = getOrCloneLoadingScreen(playerGui)
if loadingScreen then
	loadingScreen.Enabled = true
	loadingScreen:SetAttribute(LOADING_ATTRIBUTE_DATA_READY, false)
	loadingScreen:SetAttribute(LOADING_ATTRIBUTE_SKIP_REQUESTED, false)
	setLoadingProgress(loadingScreen, "Loading Data", 0)
end

applyCoreGuiState(false)
SetCharacterControlsEnabled(false)

task.spawn(preloadPlayerGuiImages, playerGui)
waitForPlayerData(loadingScreen)

if loadingScreen then
	setLoadingProgress(loadingScreen, "Initializing Controllers", 0.35)

	local skipButton: GuiButton = getSkipButton(loadingScreen)
	setSkipButtonVisible(skipButton, false)

	waitForClientInit(loadingScreen)
	setLoadingProgress(loadingScreen, "Starting Systems", 0.7)
	waitForStartOrSkip(loadingScreen, skipButton)
	setLoadingProgress(loadingScreen, "Ready", 1)
end

finishLoading(loadingScreen)
