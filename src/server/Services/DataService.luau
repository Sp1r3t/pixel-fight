--!strict
--[[
	DataService — сохранения игрока.

	  • профиль (Shared/Data/ProfileSchema) открывается при входе через хранилище с сессионной
	    блокировкой (Data/ProfileStoreBackend → ProfileStore): профиль открыт только на одном сервере,
	    поэтому нет дюпа и потери данных; при выходе сессия закрывается и данные сохраняются;
	  • не удалось открыть профиль — игрок отключается с понятным сообщением; профиль забрал другой
	    сервер — тоже (иначе изменения здесь потерялись бы);
	  • данные меняются только функциями сервиса (сервер — единственный источник правды);
	    после изменений профиль публикуется клиенту (канал "Profile" → Fusion Values в UI).
	Пока профиль загружается, функции чтения отвечают безопасными значениями по умолчанию,
	а функции изменения ничего не делают.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local Arenas = require(ReplicatedStorage.Shared.Config.Arenas)
local ControlsLayout = require(ReplicatedStorage.Shared.Config.ControlsLayout)
local ProfileSchema = require(ReplicatedStorage.Shared.Data.ProfileSchema)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)

local RequestRouter = require(script.Parent.Parent.Net.RequestRouter)
local Session = require(script.Parent.Parent.Data.Session)
local Backend = require(script.Parent.Parent.Data.ProfileStoreBackend) :: Session.Backend

type PlayerData = ProfileSchema.PlayerData

local MAX_COINS = 1e9

local DataService = {
	Name = "DataService",
}

local sessions: { [Player]: Session.Session } = {}
local loading: { [Player]: boolean } = {}
local loadedCallbacks: { (player: Player) -> () } = {}

-- Данные профиля (nil — ещё загружается или игрок вышел).
function DataService.get(player: Player): PlayerData?
	local session = sessions[player]
	return if session then session.data else nil
end

function DataService.getSession(player: Player): Session.Session?
	return sessions[player]
end

function DataService.isLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

-- Подождать загрузки профиля (для обработки покупок). nil — не дождались.
function DataService.waitForSession(player: Player, timeout: number): Session.Session?
	local deadline = os.clock() + timeout
	while sessions[player] == nil and player.Parent ~= nil and os.clock() < deadline do
		task.wait(0.25)
	end
	return sessions[player]
end

-- Вызвать callback, когда профиль игрока загружен (сразу — если уже).
function DataService.onLoaded(callback: (player: Player) -> ())
	table.insert(loadedCallbacks, callback)
	for player in sessions do
		task.spawn(callback, player)
	end
end

-- Отправить клиенту актуальный профиль.
function DataService.publish(player: Player)
	local data = DataService.get(player)
	if data == nil or player.Parent == nil then
		return
	end
	Transport.fireClient("Profile", player, ProfileSchema.toPublic(data))
end

function DataService.getControls(player: Player): ControlsLayout.Layout
	local data = DataService.get(player)
	return if data then data.controls else ControlsLayout.default()
end

-- Сохранить раскладку управления (данные от клиента проверяются sanitize).
function DataService.setControls(player: Player, raw: unknown): ControlsLayout.Layout
	local layout = ControlsLayout.sanitize(raw)
	local data = DataService.get(player)
	if data then
		data.controls = layout
	end
	return layout
end

-- Может ли игрок играть этим персонажем.
function DataService.ownsCharacter(player: Player, characterId: string): boolean
	local def = CharacterRegistry.get(characterId)
	if def == nil then
		return false
	end
	if def.unlock == "Free" then
		return true
	end
	local data = DataService.get(player)
	return data ~= nil and data.ownedCharacters[characterId] == true
end

-- Открыть платного персонажа (покупка). false — профиль не загружен или персонаж бесплатный.
function DataService.grantCharacter(player: Player, characterId: string): boolean
	local def = CharacterRegistry.get(characterId)
	local data = DataService.get(player)
	if def == nil or def.unlock ~= "Paid" or data == nil then
		return false
	end
	data.ownedCharacters[characterId] = true
	DataService.publish(player)
	return true
end

-- Доступна ли игроку карта (бесплатная или купленная премиальная).
function DataService.ownsArena(player: Player, arenaId: string): boolean
	local arena = Arenas.byId[arenaId]
	if arena == nil then
		return false
	end
	if not arena.premium then
		return true
	end
	local data = DataService.get(player)
	return data ~= nil and data.ownedArenas[arenaId] == true
end

-- Открыть премиальную карту (покупка). false — профиль не загружен или карта бесплатная.
function DataService.grantArena(player: Player, arenaId: string): boolean
	local arena = Arenas.byId[arenaId]
	local data = DataService.get(player)
	if arena == nil or not arena.premium or data == nil then
		return false
	end
	data.ownedArenas[arenaId] = true
	DataService.publish(player)
	return true
end

function DataService.getCoins(player: Player): number
	local data = DataService.get(player)
	return if data then data.coins else 0
end

function DataService.addCoins(player: Player, amount: number): boolean
	assert(amount >= 0 and amount == math.floor(amount), "Некорректная сумма")
	local data = DataService.get(player)
	if data == nil then
		return false
	end
	data.coins = math.min(MAX_COINS, data.coins + amount)
	DataService.publish(player)
	return true
end

-- Списать монеты. false — не хватает или профиль не загружен.
function DataService.spendCoins(player: Player, amount: number): boolean
	assert(amount >= 0 and amount == math.floor(amount), "Некорректная сумма")
	local data = DataService.get(player)
	if data == nil or data.coins < amount then
		return false
	end
	data.coins -= amount
	DataService.publish(player)
	return true
end

-- Сколько боссов пройдено по порядку (открыт следующий за ним).
function DataService.getBossProgress(player: Player): number
	local data = DataService.get(player)
	return if data then data.bossProgress else 0
end

--[[
	Засчитать победу над боссом с номером order (id — для учёта первых побед).
	Прогресс растёт только по порядку. Награда — только за первую победу.
	Возвращает (первая ли это победа, начисленная награда).
]]
function DataService.recordBossWin(player: Player, bossId: string, order: number, reward: number): (boolean, number)
	local data = DataService.get(player)
	if data == nil then
		return false, 0
	end
	local clears = data.bossClears[bossId] or 0
	data.bossClears[bossId] = clears + 1
	if order == data.bossProgress + 1 then
		data.bossProgress = order
	end
	local firstClear = clears == 0
	local granted = if firstClear then math.max(0, math.floor(reward)) else 0
	data.coins = math.min(MAX_COINS, data.coins + granted)
	DataService.publish(player)
	return firstClear, granted
end

local function load(player: Player)
	if loading[player] or sessions[player] then
		return -- уже загружается (PlayerAdded и Start могут встретить одного игрока дважды)
	end
	loading[player] = true
	local ok, result = pcall(Backend.start, player)
	loading[player] = nil
	local session: Session.Session? = if ok then result else nil
	if not ok then
		warn(`[DataService] Ошибка загрузки профиля {player.UserId}: {result}`)
	end
	if session == nil then
		if player.Parent ~= nil then
			player:Kick(
				"Не удалось загрузить сохранения. Попробуйте зайти ещё раз через минуту."
			)
		end
		return
	end
	if player.Parent == nil then
		session.endSession() -- вышел, пока грузили
		return
	end
	sessions[player] = session
	session.onEnded(function()
		sessions[player] = nil
		-- Сессию закрыли не мы (профиль открыт на другом сервере) — дальше играть здесь нельзя.
		local parent: Instance? = player.Parent
		if parent ~= nil then
			player:Kick(
				"Ваши сохранения открыты на другом сервере. Перезайдите в игру."
			)
		end
	end)
	for _, callback in loadedCallbacks do
		task.spawn(callback, player)
	end
	DataService.publish(player)
end

function DataService.Init()
	RequestRouter.register("SaveControls", function(player: Player, payload: unknown)
		DataService.setControls(player, payload)
		return true, nil
	end)
	RequestRouter.register("GetProfile", function(player: Player)
		local data = DataService.get(player)
		if data == nil then
			return false, "ProfileLoading" -- профиль придёт каналом Profile после загрузки
		end
		return true, ProfileSchema.toPublic(data)
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(load, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local session = sessions[player]
		sessions[player] = nil
		if session then
			session.endSession()
		end
	end)
end

function DataService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
end

return DataService
