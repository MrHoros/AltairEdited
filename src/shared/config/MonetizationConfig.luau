export type GamePassSet = {
	[string]: number,
}

export type DevProductSet = {
	[string]: DevProduct,
}

export type DevProductData = number | Data | { data: { [any]: Data } }

export type DevProduct =
	DevProductData
	& ({
		exec: Exec? | { Exec }?,
	} | {
		execs: Exec? | { Exec }?,
	})
	& ({
		offer: string? | { string }?,
	} | {
		offers: string? | { string }?,
	})

export type Data = {
	id: number,
	[any]: any?,
}

export type Exec = string | (...any) -> () | {
	name: string?,
	func: (...any) -> ()?,
	value: any?,
}

export type MonetizationProduct = DevProductSet | GamePassSet

export type MonetizationConfig = {
	passes: GamePassSet,
	products: DevProductSet,
}

local MonetizationConfig: MonetizationConfig = {
	passes = {},
	products = {},
}

return table.freeze(MonetizationConfig)
