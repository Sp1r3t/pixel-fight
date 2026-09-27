-- Комбо: список (не больше 30, простые), распознавание в симуляции, выполнимость каждого комбо.

local ComboConfig = requireShared("Config", "Combos")
local Combos = requireShared("Combat", "Combos")
local Simulation = requireShared("Combat", "Simulation")
local InputBits = requireShared("Combat", "InputBits")
local CharacterRegistry = requireShared("Characters", "CharacterRegistry")

local TOKENS = { L = true, H = true, cL = true, cH = true, jL = true, jH = true, S = true, SU = true }

local function characterIds()
	local ids = {}
	for _, def in CharacterRegistry.list() do
		table.insert(ids, def.id)
	end
	return ids
end

describe("Список комбо", function()
	it(
		"не больше 30 комбо: 12 общих и по одному фирменному на бойца",
		function()
			expect(#ComboConfig.list <= ComboConfig.MAX).toBeTruthy()
			expect(#ComboConfig.list >= 20).toBeTruthy()
			local universal, signatures = 0, {}
			for _, combo in ComboConfig.list do
				if combo.character then
					expect(CharacterRegistry.get(combo.character) ~= nil).toBeTruthy()
					expect(signatures[combo.character]).toBe(nil)
					signatures[combo.character] = true
				else
					universal += 1
				end
			end
			expect(universal).toBe(12)
			for _, id in characterIds() do
				expect(signatures[id]).toBe(true)
			end
		end
	)

	it(
		"комбо простые: 2–4 удара, понятные жетоны, у каждого есть подсказка и награда",
		function()
			local ids = {}
			for _, combo in ComboConfig.list do
				expect(ids[combo.id]).toBe(nil)
				ids[combo.id] = true
				expect(#combo.inputs >= 2 and #combo.inputs <= 4).toBeTruthy()
				for _, token in combo.inputs do
					expect(TOKENS[token]).toBe(true)
				end
				expect(#combo.hint > 0).toBeTruthy()
				expect(combo.reward > 0).toBeTruthy()
				-- Общие комбо — только обычные удары (выходят у любого бойца).
				if combo.character == nil then
					for _, token in combo.inputs do
						expect(token ~= "S" and token ~= "SU").toBeTruthy()
					end
				end
			end
		end
	)

	it("у одного бойца нет двух комбо с одинаковыми нажатиями", function()
		for _, id in characterIds() do
			local seen = {}
			for _, combo in ComboConfig.list do
				if combo.character == nil or combo.character == id then
					local key = table.concat(combo.inputs, " ")
					expect(seen[key]).toBe(nil)
					seen[key] = combo.id
				end
			end
		end
	end)
end)

describe("Распознавание комбо", function()
	it(
		"засчитывается самое длинное подходящее комбо, при равной длине — фирменное",
		function()
			local function best(character, tokens)
				local index = Combos.best(character, tokens)
				return if index then ComboConfig.list[index].id else nil
			end
			expect(best("rook", { "L", "L" })).toBe("one_two")
			expect(best("rook", { "L", "L", "H" })).toBe("classic")
			expect(best("rook", { "L", "H", "S" })).toBe("rook_vanguard")
			expect(best("dax", { "L", "L", "H", "S" })).toBe("dax_knockout")
			-- Чужое фирменное не засчитывается: у Байта «Рука, Рука, Нога, Приём» — это «Классика».
			expect(best("byte", { "L", "L", "H", "S" })).toBe("classic")
			-- Комбо может быть внутри более длинной серии.
			expect(best("mira", { "cL", "L", "H", "S", "L" })).toBe("mira_cyclone")
			expect(best("rook", { "L" })).toBe(nil)
			expect(best("rook", { "S", "H" })).toBe(nil)
		end
	)

	it(
		"в симуляции: «Классика» — событие Combo после конца серии",
		function()
			local sim = Simulation.new({ characters = { "rook", "rook" } })
			sim.fighters[1].x = -0.8
			sim.fighters[2].x = 0.8
			local combos = {}
			local function frame(pressed)
				Simulation.step(sim, { { held = 0, pressed = pressed }, { held = 0, pressed = 0 } })
				for _, event in sim.events do
					if event.kind == "Combo" then
						table.insert(combos, event)
					end
				end
			end
			-- Как игрок: жмём кнопку, пока не начнётся нужный удар, и ждём попадания.
			local steps = {
				{ bit = InputBits.Light, move = "Light1" },
				{ bit = InputBits.Light, move = "Light2" },
				{ bit = InputBits.Heavy, move = "Heavy" },
			}
			local fighter = sim.fighters[1]
			for _, step in steps do
				for _ = 1, 30 do
					if fighter.move == step.move then
						break
					end
					frame(step.bit)
				end
				expect(fighter.move).toBe(step.move)
				for _ = 1, 30 do
					if fighter.moveConnected then
						break
					end
					frame(0)
				end
			end
			for _ = 1, 120 do
				frame(0)
			end
			expect(#combos).toBe(1)
			expect(combos[1].tag).toBe("classic")
			expect(combos[1].slot).toBe(1)
			expect(combos[1].target).toBe(2)
			expect(ComboConfig.list[combos[1].value].name).toBe("Классика")
		end
	)

	it("заблокированные удары не считаются", function()
		local sim = Simulation.new({ characters = { "rook", "rook" } })
		sim.fighters[1].x = -0.8
		sim.fighters[2].x = 0.8
		local combos = 0
		for index = 1, 90 do
			local pressed = if index == 1 or index == 12 then InputBits.Light else 0
			-- Второй держит блок.
			Simulation.step(sim, { { held = 0, pressed = pressed }, { held = InputBits.Block, pressed = 0 } })
			for _, event in sim.events do
				if event.kind == "Combo" then
					combos += 1
				end
			end
		end
		expect(combos).toBe(0)
		expect(#sim.fighters[2].comboLog).toBe(0)
	end)
end)

describe("Каждое комбо выполнимо", function()
	it("общие комбо выходят у всех 16 бойцов", function()
		for _, combo in ComboConfig.list do
			if combo.character == nil then
				for _, id in characterIds() do
					local ok = ComboPerformer.perform(id, combo.inputs, combo.id)
					if not ok then
						error(`комбо {combo.id} не выходит у {id}`)
					end
				end
			end
		end
	end)

	it("фирменное комбо выходит у своего бойца", function()
		for _, combo in ComboConfig.list do
			if combo.character then
				local ok = ComboPerformer.perform(combo.character, combo.inputs, combo.id)
				if not ok then
					error(`фирменное комбо {combo.id} не выходит у {combo.character}`)
				end
			end
		end
	end)
end)

describe("Комбо в игре", function()
	-- Тренировка: игрок жмёт «Рука» с клавиатуры (через сеть), как только прошлый удар попал.
	local function jabCombo(game, client, match)
		local attacker, dummy = match.sim.fighters[1], match.sim.fighters[2]
		attacker.x, dummy.x = -0.8, 0.8
		local function tapJ()
			client.runtime.pressKey("J")
			game.step(1)
			client.runtime.releaseKey("J")
		end
		tapJ()
		for _ = 1, 30 do
			if attacker.moveConnected then
				break
			end
			game.step(1)
		end
		for _ = 1, 20 do
			if attacker.move == "Light2" then
				break
			end
			tapJ()
		end
	end

	it(
		"комбо в тренировке: название на экране, монеты за первый раз, за повтор — нет",
		function()
			local game = Harness.new()
			local client = game.addClient("Alice")
			game.step(2)
			client.click("Тренировка")
			game.step(10)
			if client.find("HowToPlay") then
				client.press("GotIt")
				game.step(1)
			end
			local MatchService = game.serverRequire("Services", "MatchService")
			local DataService = game.serverRequire("Services", "DataService")
			local match = MatchService.getMatchOf(client.player)
			local coins = DataService.getCoins(client.player)

			jabCombo(game, client, match)
			local title = nil
			for _ = 1, 120 do
				game.step(1)
				local label = client.find("ComboTitle1")
				if label and label.Visible then
					title = label.Text
				end
			end
			-- Какое именно комбо вышло, зависит от задержки сети («Двойка» или «Тройка»).
			local found = nil
			for _, combo in ComboConfig.list do
				if DataService.hasCombo(client.player, combo.id) then
					expect(found).toBe(nil)
					found = combo
				end
			end
			expect(found ~= nil).toBeTruthy()
			expect(found.character).toBe(nil)
			-- Название заглавными (кириллица тоже) и уведомление о новом комбо.
			local Format = client.require("UI", "Format")
			expect(title).toBe(Format.upper(found.name) .. "!")
			expect(Format.upper("Двойка")).toBe("ДВОЙКА")
			expect(DataService.getCoins(client.player)).toBe(coins + found.reward)
			expect(client.find("Notice").Text).toContainMatch(found.name)

			-- Повтор того же комбо — монет больше не дают.
			game.step(60)
			jabCombo(game, client, match)
			game.step(120)
			expect(DataService.getCoins(client.player)).toBe(coins + found.reward)
			expect(game.errors()).toBeEmpty()
		end
	)
end)
