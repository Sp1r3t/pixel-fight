--!strict
--[[
	DataService — данные игрока.

	Ответственность:
	• профиль игрока (Shared/Data/ProfileSchema): валюта, прогресс боссов, купленные персонажи,
	  настройки управления;
	• изменения профиля только через функции сервиса (сервер — единственный источник правды);
	• публикация профиля клиенту (канал "Profile" → Fusion Values в UI) после каждого изменения.

	До этапа 9 профиль живёт в памяти сервера. На этапе 9 хранилище заменяется на ProfileStore
	(сессионная блокировка — защита от дюпа и потери данных) без изменения API сервиса.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local ControlsLayout = require(ReplicatedStorage.Shared.Config.ControlsLayout)
local ProfileSchema = require(ReplicatedStorage.Shared.Data.ProfileSchema)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)

local RequestRouter = require(script.Parent.Parent.Net.RequestRouter)

type PlayerData = ProfileSchema.PlayerData

local DataService = {
	Name = "DataService",
}

local profiles: { [Player]: PlayerData } = {}

-- Профиль игрока (создаётся при первом обращении).
function DataService.get(player: Player): PlayerData
	local data = profiles[player]
	if data == nil then
		data = ProfileSchema.default()
		profiles[player] = data
	end
	return data
end

-- Отправить клиенту актуальный профиль.
function DataService.publish(player: Player)
	if player.Parent == nil then
		return
	end
	Transport.fireClient("Profile", player, ProfileSchema.toPublic(DataService.get(player)))
end

function DataService.getControls(player: Player): ControlsLayout.Layout
	return DataService.get(player).controls
end

-- Сохранить раскладку управления (данные от клиента проверяются sanitize).
function DataService.setControls(player: Player, data: unknown): ControlsLayout.Layout
	local layout = ControlsLayout.sanitize(data)
	DataService.get(player).controls = layout
	return layout
end

-- Может ли игрок играть этим персонажем.
function DataService.ownsCharacter(player: Player, characterId: string): boolean
	local def = CharacterRegistry.get(characterId)
	if def == nil then
		return false
	end
	return def.unlock == "Free" or DataService.get(player).ownedCharacters[characterId] == true
end

function DataService.getCoins(player: Player): number
	return DataService.get(player).coins
end

function DataService.addCoins(player: Player, amount: number)
	assert(amount >= 0 and amount == math.floor(amount), "Некорректная сумма")
	DataService.get(player).coins += amount
	DataService.publish(player)
end

-- Сколько боссов пройдено по порядку (открыт следующий за ним).
function DataService.getBossProgress(player: Player): number
	return DataService.get(player).bossProgress
end

--[[
	Засчитать победу над боссом с номером order (id — для учёта первых побед).
	Прогресс растёт только по порядку. Награда — только за первую победу.
	Возвращает (первая ли это победа, начисленная награда).
]]
function DataService.recordBossWin(player: Player, bossId: string, order: number, reward: number): (boolean, number)
	local data = DataService.get(player)
	local clears = data.bossClears[bossId] or 0
	data.bossClears[bossId] = clears + 1
	if order == data.bossProgress + 1 then
		data.bossProgress = order
	end
	local firstClear = clears == 0
	local granted = if firstClear then math.max(0, math.floor(reward)) else 0
	data.coins += granted
	DataService.publish(player)
	return firstClear, granted
end

function DataService.Init()
	RequestRouter.register("SaveControls", function(player: Player, payload: unknown)
		DataService.setControls(player, payload)
		return true, nil
	end)
	RequestRouter.register("GetProfile", function(player: Player)
		return true, ProfileSchema.toPublic(DataService.get(player))
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		profiles[player] = nil
	end)
end

function DataService.Start() end

return DataService
