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
local SetCharacterControlsEnabled = require(ReplicatedStorage.util.SetCharacterControlsEnabled)

local LocalPlayer = Players.LocalPlayer

local DATA_LOAD_TIMEOUT_SECONDS: number = 25
local FALLBACK_SUBTEXT: string = "Loading controllers 0/20"
local LOADING_SCREEN_ENABLED: boolean = BootstrapConfig.enableLoadingScreen ~= false
local LOADING_TEXT_FRAMES: { string } = { "Loading", "Loading.", "Loading..", "Loading..." }
local LOADING_TEXT_INTERVAL_SECONDS: number = 0.35
local MAX_CORE_GUI_ATTEMPTS: number = 200
local PRELOAD_BATCH_SIZE: number = 8
local RETRY_DELAY_SECONDS: number = 0.05

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

	local existing: ScreenGui? = playerGui:FindFirstChild("LoadingScreen") :: ScreenGui?
	if existing then
		return existing
	end

	local template: ScreenGui? = ReplicatedFirst:FindFirstChild("LoadingScreen") :: ScreenGui?
	if not template then
		return
	end

	local clone: ScreenGui = template:Clone()
	clone.DisplayOrder = 10_000
	clone.IgnoreGuiInset = true
	clone.ResetOnSpawn = false
	clone.Parent = playerGui

	return clone
end

local function startLoadingTextAnimation(loadingScreen: ScreenGui?): ()
	if not loadingScreen then
		return
	end

	local mainFrame: Frame? = loadingScreen:FindFirstChild("MainFrame") :: Frame?
	if not mainFrame or not mainFrame:IsA("Frame") then
		return
	end

	local loadingTextLabel: TextLabel? = mainFrame:FindFirstChild("LoadingText") :: TextLabel?
	local loadingSubTextLabel: TextLabel? = mainFrame:FindFirstChild("LoadingSubText") :: TextLabel?
	if loadingSubTextLabel and loadingSubTextLabel:IsA("TextLabel") then
		loadingSubTextLabel.Text = FALLBACK_SUBTEXT
	end

	if not loadingTextLabel or not loadingTextLabel:IsA("TextLabel") then
		return
	end

	task.spawn(function(): ()
		local frameIndex: number = 1
		while loadingScreen.Parent do
			loadingTextLabel.Text = LOADING_TEXT_FRAMES[frameIndex]
			frameIndex += 1
			if frameIndex > #LOADING_TEXT_FRAMES then
				frameIndex = 1
			end

			task.wait(LOADING_TEXT_INTERVAL_SECONDS)
		end
	end)
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

local function waitForPlayerData(): ()
	xpcall(function(): ()
		ClientData:GetPlayerProducerAsync():timeout(DATA_LOAD_TIMEOUT_SECONDS, false):expect()
	end, warn)
end

local playerGui: PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local loadingScreen: ScreenGui? = getOrCloneLoadingScreen(playerGui)
if loadingScreen then
	loadingScreen.Enabled = true
	startLoadingTextAnimation(loadingScreen)
end

applyCoreGuiState(false)
SetCharacterControlsEnabled(false)

preloadPlayerGuiImages(playerGui)
waitForPlayerData()

GetBridge("PlayerReady"):Fire()
SetCharacterControlsEnabled(true)

applyCoreGuiState(true)
