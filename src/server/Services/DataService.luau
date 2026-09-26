--!strict
--[[
	DataService — сохранения игрока.  [этап 9]

	Ответственность:
	• профиль игрока через ProfileStore (сессионная блокировка — защита от дюпа и потери данных);
	• открытые персонажи, прогресс по боссам, валюта, настройки управления;
	• миграции версий профиля и значения по умолчанию;
	• публикация состояния профиля клиенту (→ Fusion Values в UI).

	Пока (до этапа 9) профилей нет: доступны только бесплатные персонажи.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local ControlsLayout = require(ReplicatedStorage.Shared.Config.ControlsLayout)

local RequestRouter = require(script.Parent.Parent.Net.RequestRouter)

local DataService = {
	Name = "DataService",
}

-- Пока без профилей: настройки живут до конца сессии (этап 9 — сохранение в ProfileStore).
local controls: { [Player]: ControlsLayout.Layout } = {}

function DataService.getControls(player: Player): ControlsLayout.Layout
	return controls[player] or ControlsLayout.default()
end

-- Сохранить раскладку управления (данные от клиента проверяются sanitize).
function DataService.setControls(player: Player, data: unknown): ControlsLayout.Layout
	local layout = ControlsLayout.sanitize(data)
	controls[player] = layout
	return layout
end

-- Может ли игрок играть этим персонажем.
function DataService.ownsCharacter(_player: Player, characterId: string): boolean
	return CharacterRegistry.isFree(characterId)
end

function DataService.Init()
	RequestRouter.register("SaveControls", function(player: Player, payload: unknown)
		DataService.setControls(player, payload)
		return true, nil
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		controls[player] = nil
	end)
end

function DataService.Start() end

return DataService
