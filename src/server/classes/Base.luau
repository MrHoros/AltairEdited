local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Base = {}
Base.__index = Base

local BASES_FOLDER_NAME = "Bases"
local BASE_COMPONENTS_PATH = { "shared", "model", "BaseComponents", "PlayerBase" }
local REMOVED_STARTER_CHILDREN = {
	GeneratedFloors = true,
	LocalButtons = true,
	SetBrainrots = true,
	UpgradeBoard = true,
}

local function findPath(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, childName in ipairs(path) do
		if not current then
			return nil
		end

		current = current:FindFirstChild(childName)
	end

	return current
end

local function getBaseTemplate(): Model?
	local template = findPath(ReplicatedStorage, BASE_COMPONENTS_PATH)
	if template and template:IsA("Model") then
		return template
	end

	return nil
end

local function getOrCreateBasesFolder(): Folder
	local basesFolder = Workspace:FindFirstChild(BASES_FOLDER_NAME)
	if basesFolder and basesFolder:IsA("Folder") then
		return basesFolder
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = BASES_FOLDER_NAME
	newFolder.Parent = Workspace
	return newFolder
end

local function removeStarterTemplateChildren(model: Model): ()
	for childName in REMOVED_STARTER_CHILDREN do
		local child = model:FindFirstChild(childName)
		if child then
			child:Destroy()
		end
	end

	local slots = model:FindFirstChild("Slots")
	if not slots then
		slots = Instance.new("Folder")
		slots.Name = "Slots"
		slots.Parent = model
		return
	end

	for _, child in ipairs(slots:GetChildren()) do
		child:Destroy()
	end
end

local function setModelPivot(model: Model, initPart: BasePart): ()
	if model.PrimaryPart then
		model:SetPrimaryPartCFrame(initPart.CFrame)
		return
	end

	model:PivotTo(initPart.CFrame)
end

function Base.new(initPart: BasePart)
	local self = setmetatable({}, Base)

	self.Owner = nil :: Player?
	self.Reserved = false
	self.InitPart = initPart
	self.Model = nil :: Model?

	self:SetupDefaultModel()

	return self
end

function Base:SetupDefaultModel(): ()
	local template = getBaseTemplate()
	if not template then
		warn("Base: ReplicatedStorage.shared.model.BaseComponents.PlayerBase missing; cannot create base")
		return
	end

	if self.Model then
		self.Model:Destroy()
	end

	local model = template:Clone()
	model.Name = self.InitPart.Name
	setModelPivot(model, self.InitPart)
	model:SetAttribute("Owner", nil)
	model.Parent = getOrCreateBasesFolder()

	removeStarterTemplateChildren(model)

	self.Model = model
end

function Base:TeleportToBase(): ()
	if not self.Owner or not self.Model then
		return
	end

	local character = self.Owner.Character or self.Owner.CharacterAdded:Wait()
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart or not humanoidRootPart:IsA("BasePart") then
		return
	end

	local spawnPosition = self.Model:FindFirstChild("SpawnPosition")
	if spawnPosition and spawnPosition:IsA("BasePart") then
		humanoidRootPart.CFrame = spawnPosition.CFrame * CFrame.new(0, 3, 0)
	elseif self.Model.PrimaryPart then
		humanoidRootPart.CFrame = self.Model.PrimaryPart.CFrame * CFrame.new(0, 3, 0)
	end
end

function Base:SetPlayerBaseName(text: string): ()
	local ownerBoard = self.Model and self.Model:FindFirstChild("OwnerBoard")
	if not ownerBoard then
		return
	end

	local board = ownerBoard:FindFirstChild("Board")
	local surfaceGui = board and board:FindFirstChild("SurfaceGui")
	local username = surfaceGui and surfaceGui:FindFirstChild("Username")
	if username and username:IsA("TextLabel") then
		username.Text = text
	end
end

function Base:SetPlayerAvatar(player: Player?): ()
	local ownerBoard = self.Model and self.Model:FindFirstChild("OwnerBoard")
	if not ownerBoard then
		return
	end

	local board2 = ownerBoard:FindFirstChild("Board2")
	local surfaceGui = board2 and board2:FindFirstChild("SurfaceGui")
	local imageLabel = surfaceGui and surfaceGui:FindFirstChild("ImageLabel")
	if not imageLabel or not imageLabel:IsA("ImageLabel") then
		return
	end

	if not player then
		imageLabel.Visible = false
		return
	end

	imageLabel.Visible = true
	local success, thumbnail = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)

	if success then
		imageLabel.Image = thumbnail
	end
end

function Base:Reserve(player: Player): ()
	self.Reserved = true
	self.Owner = player
end

function Base:Claim(player: Player)
	self.Owner = player
	self.Reserved = false

	if not self.Model then
		self:SetupDefaultModel()
	end

	if not self.Model then
		return nil
	end

	player:SetAttribute("BaseIndex", self.Model.Name)
	self.Model:SetAttribute("Owner", player.Name)

	self:SetPlayerBaseName(`{player.Name}'s Plot`)
	self:SetPlayerAvatar(player)
	self:TeleportToBase()

	return self
end

function Base:UnClaim(): ()
	if self.Owner then
		self.Owner:SetAttribute("BaseIndex", nil)
	end

	self.Owner = nil
	self.Reserved = false
	self:SetupDefaultModel()
end

return Base
