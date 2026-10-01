local Bindings = requireShared("Config", "KeyboardBindings")
local InputBits = requireShared("Combat", "InputBits")

local function setup()
	local game = Harness.new()
	local client = game.addClient("Alice")
	game.step(3)
	client.click("Управление")
	game.step(2)
	return game, client
end

describe("Клавиши ПК", function()
	it(
		"ПК открывает редактор клавиатуры; назначение работает, сохраняется и обновляет подсказки",
		function()
			local game, client = setup()
			expect(client.find("KeyboardPanel") ~= nil).toBeTruthy()
			expect(client.find("TouchControls")).toBe(nil)
			expect(client.find("SizePlus")).toBe(nil)
			expect(client.find("KeyboardTab")).toBe(nil)
			expect(client.find("TouchTab")).toBe(nil)
			client.press("Bind_Light")
			client.runtime.pressKey("R")
			client.runtime.releaseKey("R")
			game.step(1)
			expect(client.find("Bind_Light"):FindFirstChild("Face").Text).toBe("R")
			client.press("SaveKeyboard")
			game.step(3)
			local input = client.require("Controllers", "InputController")
			expect(input.getBindingLabels("Keyboard").Light).toBe("R")
			local data = game.serverRequire("Services", "DataService")
			expect(data.getControls(client.player).keyboard.Light[1]).toBe("R")
			client.click("← Назад")
			client.click("Тренировка")
			game.step(10)
			if client.find("HowToPlay") then
				client.press("GotIt")
			end
			local match = game.serverRequire("Services", "MatchService").getMatchOf(client.player)
			match.sim.fighters[1].x = -1
			match.sim.fighters[2].x = 1
			client.runtime.pressKey("J")
			game.step(12)
			client.runtime.releaseKey("J")
			expect(match.sim.fighters[2].health).toBe(match.sim.fighters[2].maxHealth)
			client.runtime.pressKey("R")
			expect(bit32.band(input.getHeld(), InputBits.Light) ~= 0).toBeTruthy()
			game.step(12)
			client.runtime.releaseKey("R")
			expect(match.sim.fighters[2].health < match.sim.fighters[2].maxHealth).toBeTruthy()
			expect(client.find("Hint4"):FindFirstChild("Key1").Text).toBe("R")
			game.removeClient(client)
			local rejoined = game.addClient("Alice", nil, 1)
			game.step(4)
			expect(rejoined.require("Controllers", "InputController").getBindingLabels("Keyboard").Light).toBe("R")
			expect(game.errors()).toBeEmpty()
		end
	)

	it(
		"занятая клавиша отклоняется, Esc отменяет выбор, сброс возвращает стандартные клавиши",
		function()
			local game, client = setup()
			client.press("Bind_Super")
			client.runtime.pressKey("J")
			client.runtime.releaseKey("J")
			game.step(1)
			expect(client.find("Notice").Text).toContainMatch("уже назначена")
			client.runtime.pressKey("Escape")
			client.runtime.releaseKey("Escape")
			game.step(1)
			expect(client.find("Bind_Super"):FindFirstChild("Face").Text).toBe("I")
			client.press("Bind_Super")
			client.runtime.pressKey("R")
			client.runtime.releaseKey("R")
			client.press("SaveKeyboard")
			game.step(2)
			client.press("ResetKeyboard")
			client.press("SaveKeyboard")
			game.step(2)
			expect(client.require("Controllers", "InputController").getBindingLabels("Keyboard").Super).toBe("I")
			expect(game.errors()).toBeEmpty()
		end
	)

	it(
		"закрытый редактор больше не перехватывает клавиши; несохранённые изменения отменяются",
		function()
			local game, client = setup()
			client.press("Bind_Light")
			client.click("← Назад")
			client.runtime.pressKey("R")
			client.runtime.releaseKey("R")
			game.step(2)
			expect(client.require("Controllers", "InputController").getBindingLabels("Keyboard").Light).toBe("J")
			client.click("Управление")
			game.step(2)
			expect(client.find("Bind_Light"):FindFirstChild("Face").Text).toBe("J")
			expect(game.errors()).toBeEmpty()
		end
	)

	it(
		"невалидные, зарезервированные и повторяющиеся клавиши не принимаются сервером",
		function()
			for _, key in { "Escape", "Unknown", "ButtonX", "FakeKey" } do
				local raw = Bindings.default()
				raw.Light = { key }
				expect(Bindings.sanitize(raw).Light[1]).toBe("J")
			end
			local duplicate = Bindings.default()
			duplicate.Super = { "J" }
			expect(Bindings.sanitize(duplicate).Super[1]).toBe("I")
		end
	)
end)
