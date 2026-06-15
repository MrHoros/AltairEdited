local MessagingService = game:GetService("MessagingService")

local MIGRATE_TOPIC: string = "ServerMigrate_v1"
local DEFAULT_WINDOW_SECONDS: number = 60
local MAX_WINDOW_SECONDS: number = 600

return function(_context, windowSeconds: number?, force: boolean?): string
	local rolloutWindowSeconds: number = math.clamp(windowSeconds or DEFAULT_WINDOW_SECONDS, 0, MAX_WINDOW_SECONDS)
	local payload = {
		action = "migrate",
		force = force == true,
		sourceJobId = game.JobId,
		sourcePlaceVersion = game.PlaceVersion,
		windowSeconds = rolloutWindowSeconds,
	}

	local success: boolean, err: any = pcall(function(): ()
		MessagingService:PublishAsync(MIGRATE_TOPIC, payload)
	end)

	if not success then
		return `Migration signal failed: {tostring(err)}`
	end

	return `Migration signal sent. sourceVersion={game.PlaceVersion}, windowSeconds={rolloutWindowSeconds}, force={tostring(
		payload.force
	)}`
end
