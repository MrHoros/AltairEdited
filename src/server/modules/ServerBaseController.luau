local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Base = require(ServerScriptService.server.classes.Base)
local Logger = require(ReplicatedStorage.util.Logger)
local Promise = require(ReplicatedStorage.package.Promise)

local PROFILE_LOAD_WARNING_SECONDS = 15
local PROFILE_READY_RESULT = "profileReady"
local PLAYER_LEFT_RESULT = "playerLeft"
local NO_FREE_BASE_MESSAGE = "No free base slot is available on this server. Please rejoin another server."

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

local baseMutationTail = Promise.resolve()

local function isPlayerActive(player: Player): boolean
	return player.Parent == Players
end

local function chainBaseMutation(label: string, operation: () -> ...any): ()
	baseMutationTail = baseMutationTail
		:andThen(function()
			return operation()
		end)
		:catch(function(err: unknown)
			Logger.warn(`ServerBaseController[{label}]: {tostring(err)}`)
		end)
end

local function waitForProfileOrLeave(serverData: any, player: Player): any
	Promise.delay(PROFILE_LOAD_WARNING_SECONDS):andThen(function()
		if isPlayerActive(player) and serverData.GetPlayerProfile and not serverData:GetPlayerProfile(player) then
			Logger.warn(`ServerBaseController: still waiting for profile before assigning base to {player.Name}`)
		end
	end)

	return Promise.race({
		serverData:WaitForPlayerProfile(player):andThen(function()
			return PROFILE_READY_RESULT
		end),
		Promise.fromEvent(Players.PlayerRemoving, function(leavingPlayer: Player): boolean
			return leavingPlayer == player
		end):andThen(function()
			return PLAYER_LEFT_RESULT
		end),
	})
end

local function tryReserveAnyBase(player: Player): typeof(Base)?
	for _, base in ServerBaseController.Bases do
		if base:TryReserve(player) then
			return base
		end
	end

	return
end

local function releasePlayerBase(player: Player): ()
	local playerBase = ServerBaseController:GetPlayerBase(player)
	if playerBase then
		playerBase:UnClaim(player)
		return
	end

	for _, base in ServerBaseController.Bases do
		if base.Owner == player then
			base:UnClaim(player)
			return
		end
	end
end

local function claimPlayerBase(player: Player): ()
	if not isPlayerActive(player) then
		return
	end

	local reservedBase = tryReserveAnyBase(player)
	if not reservedBase then
		Logger.warn(`ServerBaseController: no free base found for {player.Name}`)
		player:Kick(NO_FREE_BASE_MESSAGE)
		return
	end

	local claimedBase = reservedBase:Claim(player)
	if not claimedBase then
		Logger.warn(`ServerBaseController: failed to claim base for {player.Name}`)
		reservedBase:UnClaim(player)
	end
end

local function waitForProfileThenClaimBase(self: Default, player: Player): any
	local serverData = self.path and self.path.controller and self.path.controller.ServerData
	if not serverData or not serverData.WaitForPlayerProfile then
		chainBaseMutation(`assign:{player.Name}`, function()
			claimPlayerBase(player)
		end)
		return
	end

	return waitForProfileOrLeave(serverData, player):andThen(function(result: string)
		if result == PLAYER_LEFT_RESULT then
			return
		end

		if not isPlayerActive(player) then
			return
		end

		chainBaseMutation(`assign:{player.Name}`, function()
			claimPlayerBase(player)
		end)
	end):catch(function(err: unknown)
		Logger.warn(`ServerBaseController: failed waiting for profile for {player.Name}: {tostring(err)}`)
	end)
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
		return
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

	return
end

function ServerBaseController:PlayerAdded(player: Player): ()
	waitForProfileThenClaimBase(self, player)
end

function ServerBaseController:PlayerRemoving(player: Player): ()
	chainBaseMutation(`release:{player.Name}`, function()
		releasePlayerBase(player)
	end)
end

return ServerBaseController
