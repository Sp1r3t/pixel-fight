--!strict
--[[
	Распознавание комбо — детерминированно, внутри симуляции боя (сервер решает, что комбо было).

	Каждое попадание (не блок) записывается в журнал защитника «жетоном»: кто ударил и чем
	(L, H, cL, cH, jL, jH, S, SU — см. Config/Combos). Многоударный приём или снаряд, попавший
	дважды подряд, — один жетон.

	Когда защитник пришёл в себя (серия закончилась) или упал в нокаут, для каждого, кто его бил,
	ищется лучшее комбо и отправляется событие "Combo": slot — кто сделал, value — номер комбо
	в Config/Combos, tag — его id, target — по кому.
]]

local ComboConfig = require(script.Parent.Parent.Config.Combos)
local SimState = require(script.Parent.SimState)
local Fighter = require(script.Parent.Fighter)

type Fighter = Fighter.Fighter
type Sim = SimState.Sim

-- Длиннее серию не записываем (защита от бесконечного журнала в редких «вечных» жонглях).
local MAX_LOG = 32

local TOKEN_OF_MOVE: { [string]: string } = {
	Light1 = "L",
	Light2 = "L",
	Light3 = "L",
	Heavy = "H",
	CrouchLight = "cL",
	CrouchHeavy = "cH",
	AirLight = "jL",
	AirHeavy = "jH",
	Special = "S",
	Super = "SU",
}

local Combos = {}

-- Жетон приёма (nil — приём не участвует в комбо).
function Combos.tokenOf(moveId: string?): string?
	return if moveId then TOKEN_OF_MOVE[moveId] else nil
end

-- Записать попадание по защитнику.
function Combos.record(defender: Fighter, attackerSlot: number, token: string)
	local log = defender.comboLog
	local last = log[#log]
	if last and last.slot == attackerSlot and last.token == token and (token == "S" or token == "SU") then
		return
	end
	if #log < MAX_LOG then
		table.insert(log, { slot = attackerSlot, token = token })
	end
end

local function contains(tokens: { string }, pattern: { ComboConfig.Token }): boolean
	local count = #pattern
	for start = 1, #tokens - count + 1 do
		local matches = true
		for offset = 1, count do
			if tokens[start + offset - 1] ~= pattern[offset] then
				matches = false
				break
			end
		end
		if matches then
			return true
		end
	end
	return false
end

--[[
	Лучшее комбо в последовательности жетонов бойца: номер в Config/Combos или nil.
	Самое длинное из подходящих; при равной длине — фирменное комбо бойца.
]]
function Combos.best(characterId: string, tokens: { string }): number?
	local best: number? = nil
	local bestLength = 0
	local bestSignature = false
	for index, combo in ComboConfig.list do
		if combo.character == nil or combo.character == characterId then
			local length = #combo.inputs
			local signature = combo.character ~= nil
			local better = length > bestLength or (length == bestLength and signature and not bestSignature)
			if better and contains(tokens, combo.inputs) then
				best, bestLength, bestSignature = index, length, signature
			end
		end
	end
	return best
end

-- Серия по защитнику закончилась: объявить комбо каждого, кто в ней участвовал.
function Combos.finish(sim: Sim, defender: Fighter)
	local log = defender.comboLog
	if #log == 0 then
		return
	end
	local order: { number } = {}
	local bySlot: { [number]: { string } } = {}
	for _, entry in log do
		local tokens = bySlot[entry.slot]
		if tokens == nil then
			tokens = {}
			bySlot[entry.slot] = tokens
			table.insert(order, entry.slot)
		end
		table.insert(tokens, entry.token)
	end
	table.clear(log)
	for _, slot in order do
		local attacker = sim.fighters[slot]
		local tokens = bySlot[slot]
		if attacker and #tokens >= 2 then
			local index = Combos.best(attacker.characterId, tokens)
			if index then
				SimState.emit(sim, "Combo", attacker, index, slot, ComboConfig.list[index].id)
				sim.events[#sim.events].target = defender.slot
			end
		end
	end
end

return Combos
