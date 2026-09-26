--!strict
--[[
	Экран «Карта боссов» — пока заглушка.  [этап 6]
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local AppState = require(script.Parent.Parent.AppState)
local PlaceholderScreen = require(script.Parent.Parent.Components.PlaceholderScreen)

type Scope = Fusion.Scope<typeof(Fusion)>

local function BossMap(scope: Scope, state: AppState.AppState): Instance
	return PlaceholderScreen(scope, {
		Title = "КАРТА БОССОВ",
		Stage = 6,
		Description = "Одиночный режим: 20 боссов по порядку, бой до 3 побед. Появится на этапе 6.",
		OnBack = function()
			AppState.back(state)
		end,
	})
end

return BossMap
