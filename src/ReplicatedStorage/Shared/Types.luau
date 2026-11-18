--!strict
-- Types.luau -- tipe data bersama server dan client.

export type SlotData = {
	Id: string, -- ID karakter (kunci Config.Characters / nama model)
	Rarity: string,
	Mutation: string, -- "Normal" | "Gold" | "Diamond" | "Rainbow" | "Void"
	PlacedAt: number, -- os.time()
}

export type PlayerData = {
	Cash: number,
	Rebirths: number,
	SlotCount: number, -- default 4, maks 10
	Slots: { [number]: SlotData },
	LastCollect: number, -- os.time()
	Version: number,
}

export type PublicState = {
	Cash: number,
	Rebirths: number,
	SlotCount: number,
	IncomePerSecond: number,
	Pending: number,
	NextSlotPrice: number?,
	RebirthCost: number,
	RebirthMultiplier: number,
	LockEndsAt: number,
	LockCooldownEndsAt: number,
	Carrying: boolean,
}

return {}
