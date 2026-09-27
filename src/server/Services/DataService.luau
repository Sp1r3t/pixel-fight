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
local Combos = require(ReplicatedStorage.Shared.Config.Combos)
local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local ProfileSchema = require(ReplicatedStorage.Shared.Data.ProfileSchema)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)

local RequestRouter = require(script.Parent.Parent.Net.RequestRouter)
local Session = require(script.Parent.Parent.Data.Session)
local Backend = require(script.Parent.Parent.Data.ProfileStoreBackend) :: Session.Backend

type PlayerData = ProfileSchema.PlayerData

-- Надетая и доступная косметика бойца в бою.
export type Loadout = { skin: string?, hitEffect: string?, koEffect: string? }

local MAX_COINS = 1e9

local DataService = {
	Name = "DataService",
}

local sessions: { [Player]: Session.Session } = {}
-- VIP-пропуск (проверяется при входе и после покупки; в профиль не пишется).
local vipPlayers: { [Player]: boolean? } = {}
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
	Transport.fireClient("Profile", player, ProfileSchema.toPublic(data, vipPlayers[player] == true))
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

--[[
	Засчитать выполненное комбо. Награда — только за первое выполнение.
	Возвращает начисленные монеты (0 — уже было, неизвестное комбо или профиль не загружен).
]]
function DataService.recordCombo(player: Player, comboId: string): number
	local data = DataService.get(player)
	local combo = Combos.byId[comboId]
	if data == nil or combo == nil or data.combos[comboId] then
		return 0
	end
	data.combos[comboId] = true
	local reward = math.max(0, math.floor(combo.reward))
	data.coins = math.min(MAX_COINS, data.coins + reward)
	DataService.publish(player)
	return reward
end

function DataService.hasCombo(player: Player, comboId: string): boolean
	local data = DataService.get(player)
	return data ~= nil and data.combos[comboId] == true
end

----------------------------------------------------------------------------------------------
-- VIP, кристаллы, косметика, ежедневная награда
----------------------------------------------------------------------------------------------

function DataService.isVip(player: Player): boolean
	return vipPlayers[player] == true
end

function DataService.setVip(player: Player, vip: boolean)
	if (vipPlayers[player] == true) ~= vip then
		vipPlayers[player] = if vip then true else nil
		DataService.publish(player)
	end
end

-- Сколько монет получит игрок за заработанные amount (VIP — больше).
function DataService.withVip(player: Player, amount: number): number
	if vipPlayers[player] then
		return math.floor(amount * Monetization.vipCoinMultiplier + 0.5)
	end
	return amount
end

-- Монеты, заработанные в бою (с бонусом VIP). Возвращает начисленное.
function DataService.addEarnedCoins(player: Player, amount: number): number
	local earned = DataService.withVip(player, math.max(0, math.floor(amount)))
	if DataService.addCoins(player, earned) then
		return earned
	end
	return 0
end

function DataService.getCrystals(player: Player): number
	local data = DataService.get(player)
	return if data then data.crystals else 0
end

function DataService.addCrystals(player: Player, amount: number): boolean
	assert(amount >= 0 and amount == math.floor(amount), "Некорректная сумма")
	local data = DataService.get(player)
	if data == nil then
		return false
	end
	data.crystals = math.min(MAX_COINS, data.crystals + amount)
	DataService.publish(player)
	return true
end

function DataService.spendCrystals(player: Player, amount: number): boolean
	assert(amount >= 0 and amount == math.floor(amount), "Некорректная сумма")
	local data = DataService.get(player)
	if data == nil or data.crystals < amount then
		return false
	end
	data.crystals -= amount
	DataService.publish(player)
	return true
end

-- Доступна ли косметика (бесплатная, купленная или VIP).
function DataService.hasItem(player: Player, itemId: string): boolean
	local data = DataService.get(player)
	return data ~= nil and ProfileSchema.hasItem(data, itemId, vipPlayers[player] == true)
end

function DataService.grantItem(player: Player, itemId: string): boolean
	local data = DataService.get(player)
	local item = Cosmetics.byId[itemId]
	if data == nil or item == nil then
		return false
	end
	if item.currency == "Coins" or item.currency == "Crystals" then
		data.items[itemId] = true
	end
	DataService.publish(player)
	return true
end

--[[
	Надеть косметику. itemId = nil — снять (slot: "Skin:<id бойца>", "HitEffect", "KoEffect").
	Возвращает false, если вещи нет или она не подходит к слоту.
]]
function DataService.equip(player: Player, slot: string, itemId: string?): boolean
	local data = DataService.get(player)
	if data == nil then
		return false
	end
	local characterId = string.match(slot, "^Skin:(.+)$")
	if itemId ~= nil then
		local item = Cosmetics.byId[itemId]
		if item == nil or not DataService.hasItem(player, itemId) then
			return false
		end
		if characterId then
			if item.kind ~= "Skin" or item.character ~= characterId then
				return false
			end
		elseif item.kind ~= slot then
			return false
		end
	end
	if characterId then
		if CharacterRegistry.get(characterId) == nil then
			return false
		end
		(data.equipped.skins :: { [string]: string? })[characterId] = itemId
	elseif slot == "HitEffect" then
		data.equipped.hitEffect = itemId
	elseif slot == "KoEffect" then
		data.equipped.koEffect = itemId
	else
		return false
	end
	DataService.publish(player)
	return true
end

-- Надетая косметика, которая сейчас доступна (VIP мог закончиться — тогда не показываем).
function DataService.getLoadout(
	player: Player,
	characterId: string
): { skin: string?, hitEffect: string?, koEffect: string? }
	local data = DataService.get(player)
	if data == nil then
		return { skin = nil, hitEffect = nil, koEffect = nil }
	end
	local function available(id: string?): string?
		return if id and DataService.hasItem(player, id) then id else nil
	end
	return {
		skin = available(data.equipped.skins[characterId]),
		hitEffect = available(data.equipped.hitEffect),
		koEffect = available(data.equipped.koEffect),
	}
end

--[[
	Ежедневная награда. now — os.time() (параметр — для тестов).
	Раз в сутки (UTC): день серии 1..7 → монеты (Monetization.dailyCoins), на 7-й — ещё кристаллы;
	пропуск дня — серия сначала. VIP: монеты ×1.5 и кристаллы каждый день.
	Возвращает (выдано ли, день серии, монеты, кристаллы).
]]
function DataService.claimDaily(player: Player, now: number): (boolean, number, number, number)
	local data = DataService.get(player)
	if data == nil then
		return false, 0, 0, 0
	end
	local today = math.floor(now / 86400)
	local daily = data.daily
	if daily.day == today then
		return false, daily.streak, 0, 0
	end
	local streak = if daily.day == today - 1 then daily.streak % 7 + 1 else 1
	local coins = DataService.withVip(player, Monetization.dailyCoins[streak] or 100)
	local crystals = (if streak == 7 then Monetization.dailyCrystalsDay7 else 0)
		+ (if vipPlayers[player] then Monetization.vipDailyCrystals else 0)
	daily.day = today
	daily.streak = streak
	data.coins = math.min(MAX_COINS, data.coins + coins)
	data.crystals = math.min(MAX_COINS, data.crystals + crystals)
	DataService.publish(player)
	return true, streak, coins, crystals
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
	local granted = if firstClear then DataService.withVip(player, math.max(0, math.floor(reward))) else 0
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
		vipPlayers[player] = nil
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
