export type BootstrapConfig = {
	introCutsceneName: string?,
	enableLoadingScreen: boolean,
	enableDeathScreen: boolean,
}

local bootstrapConfig: BootstrapConfig = {
	introCutsceneName = nil,
	enableLoadingScreen = true,
	enableDeathScreen = true,
}

return table.freeze(bootstrapConfig)
