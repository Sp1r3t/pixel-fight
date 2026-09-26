--!strict
--[[
	Экран «Магазин» — пока заглушка.  [этап 9]
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local AppState = require(script.Parent.Parent.AppState)
local PlaceholderScreen = require(script.Parent.Parent.Components.PlaceholderScreen)

type Scope = Fusion.Scope<typeof(Fusion)>

local function Shop(scope: Scope, state: AppState.AppState): Instance
	return PlaceholderScreen(scope, {
		Title = "МАГАЗИН",
		Stage = 9,
		Description = "Платные персонажи и «Пропустить босса». Появится на этапе 9.",
		OnBack = function()
			AppState.back(state)
		end,
	})
end

return Shop
