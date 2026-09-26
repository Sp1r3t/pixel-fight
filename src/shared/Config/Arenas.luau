--!strict
--[[
	Арены — только визуальные темы (цвета неба, пола, силуэтов фона). На бой не влияют.
]]

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type ArenaTheme = {
	id: string,
	name: string,
	skyTop: string,
	skyBottom: string,
	far: string, -- дальние силуэты (горы/здания)
	near: string, -- ближние силуэты
	floor: string,
	floorLine: string,
	accent: string,
	silhouette: "Mountains" | "City" | "Pillars" | "Spikes" | "Waves",
}

local Arenas: { ArenaTheme } = {
	{
		id = "dojo",
		name = "Dojo",
		skyTop = "#2B1B3D",
		skyBottom = "#E07A5F",
		far = "#3D2C4E",
		near = "#1E1428",
		floor = "#6B4A33",
		floorLine = "#8C6444",
		accent = "#FFC845",
		silhouette = "Pillars",
	},
	{
		id = "rooftop",
		name = "Neon Rooftop",
		skyTop = "#0B0B23",
		skyBottom = "#3A1C71",
		far = "#1C1446",
		near = "#120C2C",
		floor = "#2E2E3A",
		floorLine = "#FF3CAC",
		accent = "#00F5A0",
		silhouette = "City",
	},
	{
		id = "peaks",
		name = "Wind Peaks",
		skyTop = "#4A90C2",
		skyBottom = "#D6ECF3",
		far = "#7FA7C9",
		near = "#4E6E8E",
		floor = "#8A8F98",
		floorLine = "#B8BEC7",
		accent = "#FFFFFF",
		silhouette = "Mountains",
	},
	{
		id = "harbor",
		name = "Sunset Harbor",
		skyTop = "#FF7E5F",
		skyBottom = "#FEB47B",
		far = "#B85C5C",
		near = "#6B2F3A",
		floor = "#5C4033",
		floorLine = "#7A5A45",
		accent = "#2EC4B6",
		silhouette = "Waves",
	},
	{
		id = "caldera",
		name = "Caldera",
		skyTop = "#1A0500",
		skyBottom = "#8C1C00",
		far = "#4A0E00",
		near = "#240600",
		floor = "#3B2A26",
		floorLine = "#FF6B35",
		accent = "#FFE66D",
		silhouette = "Spikes",
	},
	{
		id = "void",
		name = "Star Void",
		skyTop = "#05030B",
		skyBottom = "#1A1446",
		far = "#2A1F5C",
		near = "#120C2C",
		floor = "#231A42",
		floorLine = "#C77DFF",
		accent = "#F7F1E3",
		silhouette = "Spikes",
	},
}

local byId: { [string]: ArenaTheme } = {}
for _, arena in Arenas do
	byId[arena.id] = arena
end

return deepFreeze({
	list = Arenas,
	byId = byId,
	default = "dojo",
})
