local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.package.Signal)

local signals = {}

return function(signalName: string): Signal.Signal<nil>
	if not signals[signalName] then
		signals[signalName] = Signal.new()
	end

	return signals[signalName]
end
