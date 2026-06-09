local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Base = require(ServerScriptService.server.classes.Base)
local Logger = require(game:GetService("ReplicatedStorage").util.Logger)

export type Default = {
	index: number,
	type: string,
	path: any?,
	Bases: { [number]: typeof(Base) },
	Init: (self: Default) -> (),
	PlayerAdded: (self: Default, player: Player) -> (),
	PlayerRemoving: (self: Default, player: Player) -> (),
	GetPlayerBase: (self: Default, player: Player) -> typeof(Base)?,
}

local ServerBaseController: Default = {} :: Default
ServerBaseController.index = 1
ServerBaseController.type = "controller"
ServerBaseController.Bases = {}

local function findFreeBase()
	for _, base in ServerBaseController.Bases do
		if not base.Reserved and not base.Owner then
			return base
		end
	end

	return nil
end

function ServerBaseController:Init(): ()
	local baseInitSlot = Workspace:FindFirstChild("BaseInitSlot")
	if not baseInitSlot then
		Logger.warn("ServerBaseController: workspace.BaseInitSlot missing; skipping base setup")
		return
	end

	local created = 0
	for _, child in ipairs(baseInitSlot:GetChildren()) do
		if not child:IsA("BasePart") then
			continue
		end

		local index = tonumber(child.Name)
		if not index then
			Logger.warn(`ServerBaseController: BaseInitSlot child "{child.Name}" is not numeric; skipping`)
			continue
		end

		self.Bases[index] = Base.new(child)
		created += 1
	end

	Logger.print(`ServerBaseController: initialized {created} base slot(s)`)
end

function ServerBaseController:GetPlayerBase(player: Player): typeof(Base)?
	local baseIndex = player:GetAttribute("BaseIndex")
	if baseIndex == nil then
		return nil
	end

	local numericIndex = tonumber(baseIndex)
	if numericIndex then
		return self.Bases[numericIndex]
	end

	for _, base in self.Bases do
		if base.Model and base.Model.Name == tostring(baseIndex) then
			return base
		end
	end

	return nil
end

function ServerBaseController:PlayerAdded(player: Player): ()
	local freeBase = findFreeBase()
	if not freeBase then
		Logger.warn(`ServerBaseController: no free base found for {player.Name}`)
		return
	end

	freeBase:Reserve(player)

	local serverData = self.path and self.path.controller and self.path.controller.ServerData
	if serverData and serverData.WaitForPlayerProfile then
		local loaded = serverData:WaitForPlayerProfile(player):timeout(15, false):await()
		if not loaded then
			Logger.warn(`ServerBaseController: profile load timed out for {player.Name}; releasing reserved base`)
			freeBase:UnClaim()
			return
		end
	end

	local claimedBase = freeBase:Claim(player)
	if not claimedBase then
		Logger.warn(`ServerBaseController: failed to claim base for {player.Name}`)
		freeBase:UnClaim()
		return
	end
end

function ServerBaseController:PlayerRemoving(player: Player): ()
	local playerBase = self:GetPlayerBase(player)
	if playerBase then
		playerBase:UnClaim()
		return
	end

	for _, base in self.Bases do
		if base.Owner == player then
			base:UnClaim()
			return
		end
	end
end

return ServerBaseController
