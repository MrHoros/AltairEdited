return {
	Name = "MigrateAll",
	Aliases = { "migrate-all", "migrate" },
	Description = "Migrates old public servers to the currently published place version.",
	Group = "Admin",
	Args = {
		{
			Name = "windowSeconds",
			Type = "number",
			Description = "Optional random rollout window in seconds. Defaults to 60.",
			Optional = true,
		},
		{
			Name = "force",
			Type = "boolean",
			Description = "Also migrate servers on the same or newer place version.",
			Optional = true,
		},
	},
}
