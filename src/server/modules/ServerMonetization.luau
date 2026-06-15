local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local APIDictionaries = require(ReplicatedStorage.shared.types.APIDictionaries)
local Bridgenet2 = require(ReplicatedStorage.package.Bridgenet2)
local Conditions = require(ReplicatedStorage.shared.modules.Conditions)
local GetBridge = require(ReplicatedStorage.util.GetBridge)
local InitializerTypes = require(ReplicatedStorage.shared.types.InitializerTypes)
local Logger = require(ReplicatedStorage.util.Logger)
local Maid = require(ReplicatedStorage.package.Maid)
local MonetizationConfig = require(ReplicatedStorage.shared.config.MonetizationConfig)
local MonetizationExecs = require(ServerScriptService.server.serverConfig.MonetizationExecs)
local Promise = require(ReplicatedStorage.package.Promise)
local SecurePlayerAsync = require(ReplicatedStorage.util.SecurePlayerAsync)
local ServerData = require(ServerScriptService.server.modules.ServerData)

local Notify = GetBridge("Notification")

export type ServerMonetization = {
	index: number?,
	type: string?,
	path: InitializerTypes.ServerPath,
	idIndexedMonetizationReference: { passes: { [string]: string }, products: { name: string, dataName: string? } },
	Start: (self: ServerMonetization) -> (),
	Init: (self: ServerMonetization) -> (),
	PlayerAdded: (self: ServerMonetization, player: Player) -> (),
	CheckGamePass: (self: ServerMonetization, player: Player, name: string) -> boolean,
	CheckOffer: (self: ServerMonetization, player: Player, name: string) -> boolean,
	ProcessDevProductReceipt: (
		self: ServerMonetization,
		player: Player,
		receiptInfo: APIDictionaries.receiptInfo
	) -> boolean,
	ProceedGamePassPurchaseAsync: (
		self: ServerMonetization,
		player: Player,
		id: number
	) -> Promise.TypedPromise<boolean>,
	ProceedDevProductPurchaseAsync: (
		self: ServerMonetization,
		player: Player,
		id: number
	) -> Promise.TypedPromise<boolean>,
	PromptGamePassByNameAsync: (
		self: ServerMonetization,
		player: Player,
		name: string
	) -> Promise.TypedPromise<boolean>,
	PromptDevProductByNameAsync: (
		self: ServerMonetization,
		player: Player,
		name: string,
		productName: string?
	) -> Promise.TypedPromise<boolean>,
	PromptGamePassByDataAsync: (
		self: ServerMonetization,
		player: Player,
		set: MonetizationConfig.Data
	) -> Promise.TypedPromise<boolean>,
	PromptDevProductByDataAsync: (
		self: ServerMonetization,
		player: Player,
		set: MonetizationConfig.Data
	) -> Promise.TypedPromise<boolean>,
}

local ServerMonetization: ServerMonetization = {} :: ServerMonetization
ServerMonetization.type = "controller"
ServerMonetization.index = 2
ServerMonetization.idIndexedMonetizationReference = {} :: any

local SUPPORT_NOTIFICATION_COLOR: Color3 = Color3.new(0.85, 0.5, 0.9)
local GAMEPASS_OWNERSHIP_RETRY_COUNT: number = 3
local GAMEPASS_OWNERSHIP_RETRY_DELAY_SECONDS: number = 1

local function applyGamePassOwnership(player: Player, producer: any, passName: string, showNotification: boolean): ()
	if producer.secureAddGamePass then
		producer.secureAddGamePass(passName)
	end

	if showNotification then
		Notify:Fire(Bridgenet2.Players({ player }), {
			text = "Thanks for your support!",
			seconds = 4,
			color = SUPPORT_NOTIFICATION_COLOR,
		})
	end
end

local function ownsGamePassWithRetry(player: Player, passName: string, passId: number): boolean
	local attempt: number = 1
	local lastError: any = nil
	while attempt <= GAMEPASS_OWNERSHIP_RETRY_COUNT do
		local success: boolean, ownsOrError: any = pcall(function(): boolean
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)

		if success and ownsOrError == true then
			return true
		end

		if not success then
			lastError = ownsOrError
		end

		if attempt < GAMEPASS_OWNERSHIP_RETRY_COUNT then
			task.wait(GAMEPASS_OWNERSHIP_RETRY_DELAY_SECONDS)
		end

		attempt += 1
	end

	if lastError ~= nil then
		Logger.warn(
			`ServerMonetization: UserOwnsGamePassAsync failed for player={player.Name} passName={passName} passId={passId} error={tostring(
				lastError
			)}`
		)
	end

	return false
end

function ServerMonetization:ProceedGamePassPurchaseAsync(player: Player, id: number): Promise.TypedPromise<boolean>
	return SecurePlayerAsync(
		player,
		Promise.new(function(resolve: (boolean) -> (), _reject: () -> (), onCancel: ((() -> ())?) -> ()): ()
			if not player then
				return onCancel()
			end

			MarketplaceService:PromptGamePassPurchase(player, id)

			local maid: Maid.Maid = Maid.new()
			onCancel(function(): ()
				maid:DoCleaning()
			end)

			maid:GiveTask(
				MarketplaceService.PromptGamePassPurchaseFinished:Connect(
					function(eventPlayer: Player, gamePassId: number, wasPurchased: boolean): ()
						if eventPlayer == player and gamePassId == id then
							maid:DoCleaning()
							resolve(wasPurchased)
						end
					end
				)
			)

			return
		end)
	):catch(warn)
end

function ServerMonetization:ProceedDevProductPurchaseAsync(player: Player, id: number): Promise.TypedPromise<boolean>
	return SecurePlayerAsync(
		player,
		Promise.new(function(resolve: (boolean) -> (), _reject: () -> (), onCancel: ((() -> ())?) -> ()): ()
			if not player then
				return onCancel()
			end

			MarketplaceService:PromptProductPurchase(player, id)

			local maid: Maid.Maid = Maid.new()
			onCancel(function(): ()
				maid:DoCleaning()
			end)

			maid:GiveTask(
				MarketplaceService.PromptProductPurchaseFinished:Connect(
					function(userId: number, productId: number, isPurchased: boolean): ()
						if userId == player.UserId and productId == id then
							maid:DoCleaning()
							resolve(isPurchased)
						end
					end
				)
			)

			return
		end)
	):catch(warn)
end

function ServerMonetization:PromptGamePassByNameAsync(player: Player, name: string): Promise.TypedPromise<boolean>
	return Promise.new(function(resolve: (boolean) -> (), reject: (string) -> ()): ()
		local passId: number = MonetizationConfig.passes[name]
		if not passId then
			reject(`"{name}" is not a valid member of MonetizationConfig.passes`)
			return
		end

		local status: boolean, _value: boolean =
			SecurePlayerAsync(player, self:ProceedGamePassPurchaseAsync(player, passId)):await()
		if status then
			local producer = ServerData:GetPlayerProducerAsync(player):expect()
			applyGamePassOwnership(player, producer, name, false)
		end
		resolve(status)
	end):catch(warn)
end

function ServerMonetization:PromptDevProductByNameAsync(
	player: Player,
	name: string,
	productName: string?
): Promise.TypedPromise<boolean>
	return Promise.new(function(resolve: (boolean) -> (), reject: (string) -> ()): ()
		local product: MonetizationConfig.DevProduct & any = MonetizationConfig.products[name]
		if not product then
			if name == "Luck" then
				Logger.warn(
					`ServerMonetization: PromptDevProductByNameAsync called with invalid product group name={name}`
				)
			end

			reject(`"{name}" is not a valid member of MonetizationConfig.products`)

			return
		end

		local justId: number? = type(product) == "number" and product or nil
		local data = productName and type(product) ~= "number" and (product.data[productName] or product) or nil
		if not justId and not data then
			if name == "Luck" then
				Logger.warn(
					`ServerMonetization: PromptDevProductByNameAsync invalid entry: name={name}, productName={tostring(
						productName
					)}`
				)
			end

			reject(`"{productName}" is not a valid member of MonetizationConfig.products["{name}"]`)

			return
		end

		local promptId: number = justId or data.id
		if name == "Luck" then
			Logger.print(
				`ServerMonetization: prompting dev product name={name}, productName={tostring(productName)}, id={promptId}`
			)
		end

		local status: boolean, value: boolean =
			SecurePlayerAsync(player, self:ProceedDevProductPurchaseAsync(player, promptId)):await()
		if name == "Luck" then
			Logger.print(
				`ServerMonetization: dev product prompt finished name={name}, productName={tostring(productName)}, id={promptId}, awaitStatus={tostring(
					status
				)}, purchased={tostring(value)}`
			)
		end
		resolve(status)
	end):catch(warn)
end

function ServerMonetization:PromptGamePassByDataAsync(
	player: Player,
	set: MonetizationConfig.Data
): Promise.TypedPromise<boolean>
	return Promise.new(function(resolve: (boolean) -> (), reject: (string) -> ()): ()
		local id: number = type(set) == "number" and set or set.id
		if not id then
			reject(`Id property not found in "{set}"`)

			return
		end

		local status: boolean, _value: boolean =
			SecurePlayerAsync(player, self:ProceedGamePassPurchaseAsync(player, id)):await()
		resolve(status)
	end):catch(warn)
end

function ServerMonetization:PromptDevProductByDataAsync(
	player: Player,
	set: MonetizationConfig.Data
): Promise.TypedPromise<boolean>
	return Promise.new(function(resolve: (boolean) -> (), reject: (string) -> ()): ()
		local id: number = type(set) == "number" and set or set.id
		if not id then
			reject(`Id property not found in "{set}"`)

			return
		end

		local status: boolean, _value: boolean =
			SecurePlayerAsync(player, self:ProceedDevProductPurchaseAsync(player, id)):await()
		resolve(status)
	end):catch(warn)
end

function ServerMonetization:CheckGamePass(player: Player, name: string): boolean
	return Conditions:CheckCondition(player, "passes", name)
end

function ServerMonetization:PlayerAdded(player: Player): ()
	task.spawn(function(): ()
		local producer = ServerData:GetPlayerProducerAsync(player):expect()
		local state = producer:getState()
		local storedPasses: any = state.monetization and state.monetization.passes
		for name: string, passId: number in MonetizationConfig.passes :: MonetizationConfig.GamePassSet do
			local owns: boolean = ownsGamePassWithRetry(player, name, passId)
			local storedOwns: boolean = storedPasses and storedPasses[name] == true
			if owns or storedOwns then
				applyGamePassOwnership(player, producer, name, false)
			end
		end
	end)
end

function ServerMonetization:CheckOffer(player: Player, name: string): boolean
	return Conditions:CheckCondition(player, "offers", name)
end

function ServerMonetization:ProcessDevProductReceipt(player: Player, receiptInfo: APIDictionaries.receiptInfo): boolean
	local productId: string = tostring(receiptInfo.ProductId)
	local data = self.idIndexedMonetizationReference.products[productId]
	if not data then
		Logger.warn(`No idIndexed data for dev product (id: {productId})`)

		return false
	end

	local config = MonetizationConfig.products[data.name]
	if not config then
		Logger.warn(
			`No dev product found in config with name: {data.name}{data.dataName and ` and entry name: {data.dataName}` or ""}`
		)

		return false
	end

	local entryConfig = data.dataName
			and config
			and config.data
			and config.data[data.dataName]
			and config.data[data.dataName]
		or nil

	local execs = (entryConfig and (entryConfig.exec or entryConfig.execs)) or config.exec or config.execs
	execs = execs and type(execs) ~= "table" and { execs } or execs or {}
	for _index: number, execNameOrFunction: string | (...any) -> () in execs do
		local exec = type(execNameOrFunction) == "string" and MonetizationExecs.execs[execNameOrFunction]
			or type(execNameOrFunction) == "function" and execNameOrFunction
		if not exec then
			Logger.warn(`No exec found with name: {execNameOrFunction}`)

			return false
		end

		local success: boolean, err: any = xpcall(function(): ()
			exec(player, data, config)
		end, debug.traceback)
		if not success then
			Logger.warn(`Dev product exec failed for product id {productId}: {tostring(err)}`)

			return false
		end
	end

	local offers = (entryConfig and (entryConfig.offer or entryConfig.offers)) or config.offer or config.offers
	offers = offers and type(offers) == "string" and { offers } or offers or {}
	if #offers > 0 then
		local producer = ServerData:GetPlayerProducerAsync(player):expect()

		for _index: number, offerName: string in offers do
			producer.secureAddOffer(offerName)

			local offerExec: (() -> ())? = MonetizationExecs.offers[offerName]
			if offerExec then
				local success: boolean, err: any = xpcall(offerExec, debug.traceback)
				if not success then
					Logger.warn(`Offer exec failed for offer {offerName}: {tostring(err)}`)

					return false
				end
			end
		end
	end

	Notify:Fire(Bridgenet2.Players({ player }), {
		text = "Thanks for your support!",
		seconds = 4,
		color = SUPPORT_NOTIFICATION_COLOR,
	})

	if not ServerData:SavePlayerProfile(player) then
		Logger.warn(
			`ServerMonetization: failed to persist profile after dev product receipt player={player.Name} productId={productId}`
		)
	end

	return true
end

function ServerMonetization:Start(): ()
	MarketplaceService.ProcessReceipt = function(receiptInfo: APIDictionaries.receiptInfo): Enum.ProductPurchaseDecision
		local player: Player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local success: boolean, wasProcessed: boolean = xpcall(function(): boolean
			return self:ProcessDevProductReceipt(player, receiptInfo)
		end, debug.traceback)
		if success and wasProcessed then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		if not success then
			Logger.warn(`ProcessReceipt failed for product id {receiptInfo.ProductId}: {tostring(wasProcessed)}`)
		end

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

function ServerMonetization:Init(): ()
	GetBridge("MonetizationPrompt"):Connect(
		function(player: Player, data: { name: string, isGamePass: boolean?, productName: string? } | any): ()
			if typeof(data) ~= "table" then
				return
			end

			local name: any = data.name
			if typeof(name) ~= "string" then
				return
			end

			local productName: any = data.productName
			if productName ~= nil and typeof(productName) ~= "string" then
				productName = nil
			end

			local isGamePass: boolean = data.isGamePass == true
			local request: Promise.TypedPromise<boolean>
			if isGamePass then
				request = self:PromptGamePassByNameAsync(player, name)
			else
				request = self:PromptDevProductByNameAsync(player, name, productName)
			end

			local resolvedSuccess: boolean = false
			local resolvedError: any = nil

			request
				:andThen(function(status: boolean): ()
					resolvedSuccess = status == true
				end)
				:catch(function(err: any): ()
					resolvedSuccess = false
					resolvedError = err
				end)
				:finally(function(): ()
					GetBridge("MonetizationPrompt"):Fire(player, {
						name = name,
						isGamePass = isGamePass,
						productName = productName,
						success = resolvedSuccess,
						completed = true,
						error = resolvedError,
					})
				end)
		end
	)

	self.idIndexedMonetizationReference.passes = {}
	for name: string, id: number in MonetizationConfig.passes :: MonetizationConfig.GamePassSet do
		self.idIndexedMonetizationReference.passes[tostring(id)] = name
	end

	self.idIndexedMonetizationReference.products = {}
	for name: string, data: MonetizationConfig.DevProductData & any in MonetizationConfig.products :: any do
		local products = self.idIndexedMonetizationReference.products
		local id: string? = type(data) == "number" and data or data.id
		id = id and tostring(id) or nil
		if id then
			products[id] = {
				name = name,
			}
		elseif type(data) == "table" and data.data then
			for dataEntryName: string, entryData: MonetizationConfig.Data & any in data.data :: any do
				id = entryData.id and tostring(entryData.id) or nil
				if not id then
					Logger.warn(`Invalid DevProductData for "{dataEntryName}" in "{name}", no id found!`)

					continue
				end

				if products[id] then
					local oldData = { products[id].name, products[id].dataName }
					local newData = { name, dataEntryName }

					Logger.warn(
						`Dev product with id {id} is already indexed!`
							.. ` Overwriting "{table.concat(oldData, `", "`)}" with "{table.concat(newData, `", "`)}"...`
					)
				end

				products[id] = {
					name = name,
					dataName = dataEntryName,
				}
			end
		else
			Logger.warn(`Invalid DevProductData for "{name}", no id or data found!`)
		end
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, wasPurchased: boolean): ()
			if not wasPurchased then
				return
			end

			local producer = ServerData:GetPlayerProducerAsync(player):expect()
			local passName: string? = self.idIndexedMonetizationReference.passes[tostring(passId)]
			if passName then
				applyGamePassOwnership(player, producer, passName, true)
			end
		end
	)
end

return ServerMonetization
