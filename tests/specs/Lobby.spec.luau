local BotNames = requireShared("Config", "BotNames")

describe("Игровые ники", function()
	it(
		"100 уникальных ников; случайный выбор не повторяет занятые имена",
		function()
			expect(#BotNames.list).toBe(100)
			local used = {}
			for _, name in BotNames.list do
				expect(used[string.lower(name)]).toBe(nil)
				expect(string.match(name, "^[a-z0-9_]+$") ~= nil).toBeTruthy()
				used[string.lower(name)] = true
			end
			used[BotNames.list[50]] = nil
			local random = {
				NextInteger = function(_, first, _last)
					return first
				end,
			}
			expect(BotNames.pick(random, used)).toBe(BotNames.list[50])
			local picked = {}
			for _ = 1, 100 do
				local name = BotNames.pick(random, picked)
				expect(picked[name]).toBe(nil)
				picked[name] = true
			end
		end
	)
end)

describe("Подсказки лобби", function()
	it(
		"наведение, нажатие и уход возвращают кнопки в исходное положение",
		function()
			local game = Harness.new()
			local client = game.addClient("Alice")
			game.step(3)
			local tile = client.find("Tile1")
			local face, plate = tile:FindFirstChild("Face", true), tile:FindFirstChild("Plate")
			client.runtime.fire(face, "MouseEnter")
			game.step(60)
			expect(plate.Position.Y.Offset < -2.9).toBeTruthy()
			client.runtime.fire(face, "MouseButton1Down")
			game.step(60)
			expect(plate.Position.Y.Offset > 1.9).toBeTruthy()
			client.runtime.fire(face, "MouseLeave")
			game.step(60)
			expect(math.abs(plate.Position.Y.Offset) < 0.01).toBeTruthy()
			local button = client.find("Combos")
			local buttonFace, body = button:FindFirstChild("Face"), button:FindFirstChild("Body")
			client.runtime.fire(buttonFace, "SelectionGained")
			game.step(60)
			expect(body.Position.Y.Offset < -1.9).toBeTruthy()
			client.runtime.fire(buttonFace, "SelectionLost")
			game.step(60)
			expect(math.abs(body.Position.Y.Offset) < 0.01).toBeTruthy()
			expect(game.errors()).toBeEmpty()
			expect(game.warnings()).toBeEmpty()
		end
	)
	it(
		"мультиплеер показывает ники людей и пиксельные значки с текущими клавишами",
		function()
			local game = Harness.new()
			local alice, bob = game.addClient("Alice"), game.addClient("Bob")
			game.step(3)
			local mm = game.serverRequire("Services", "MatchmakingService")
			mm.startMatch("Versus", {
				{ player = alice.player, characterId = "rook" },
				{ player = bob.player, characterId = "brakk" },
			}, true)
			game.step(3)
			alice.press("DraftReady")
			bob.press("DraftReady")
			game.step(3)
			alice.runtime.fire(alice.find("Map_dojo"), "Activated")
			bob.runtime.fire(bob.find("Map_dojo"), "Activated")
			game.step(120)
			expect(alice.find("FighterPanel2"):FindFirstChild("Name").Text).toBe("BOB")
			expect(bob.find("FighterPanel1"):FindFirstChild("Name").Text).toBe("ALICE")
			local state = alice.require("Controllers", "UIController").getState()
			local input = alice.require("Controllers", "InputController")
			local bindings = input.getBindingLabels("Keyboard")
			bindings.Super = "CUSTOM_SUPER"
			state.inputBindings:set(bindings)
			game.step(1)
			local hint = alice.find("ControlsHint"):FindFirstChild("Hint7")
			expect(hint:FindFirstChild("Key1").Text).toBe("CUSTOM_SUPER")
			expect(hint:FindFirstChild("ActionIcon").ClassName).toBe("Frame")
			expect(hint:FindFirstChild("Text").Text).toBe("супер")
			expect(game.errors()).toBeEmpty()
		end
	)
	it(
		"на ПК все советы используют текущие бинды, на телефоне — сенсорные кнопки",
		function()
			local game = Harness.new()
			local client = game.addClient("Alice")
			game.step(3)
			local state = client.require("Controllers", "UIController").getState()
			state.inputBindings:set({
				Move = "CUSTOM_MOVE",
				Crouch = "CUSTOM_CROUCH",
				Block = "CUSTOM_BLOCK",
				Super = "CUSTOM_SUPER",
				Dash = "CUSTOM_DASH",
				Light = "CUSTOM_LIGHT",
				Heavy = "CUSTOM_HEAVY",
				Jump = "CUSTOM_JUMP",
				Special = "CUSTOM_SPECIAL",
			})
			for _ = 1, 7 do
				game.step(1)
				local text = client.find("Tip").Text
				expect(string.find(text, "CUSTOM_", 1, true) ~= nil).toBeTruthy()
				expect(string.find(text, "джойстик", 1, true)).toBe(nil)
				expect(string.find(text, "молнии", 1, true)).toBe(nil)
				expect(client.find("Bulb").ClassName).toBe("Frame")
				client.runtime.services.RunService.RenderStepped:Fire(7)
			end
			client.runtime.services.UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Touch)
			game.step(2)
			for _ = 1, 7 do
				local text = client.find("Tip").Text
				expect(string.find(text, "CUSTOM_", 1, true)).toBe(nil)
				expect(string.find(text, "клавиш", 1, true)).toBe(nil)
				client.runtime.services.RunService.RenderStepped:Fire(7)
				game.step(1)
			end
			expect(game.errors()).toBeEmpty()
		end
	)

	it(
		"подписи клавиш соответствуют управлению и переключаются вместе с устройством",
		function()
			local game = Harness.new()
			local client = game.addClient("Alice")
			game.step(3)
			local input = client.require("Controllers", "InputController")
			expect(input.getBindingLabels("Keyboard").Super).toBe("I")
			expect(input.getBindingLabels("Keyboard").Light).toBe("J")
			expect(input.getBindingLabels("Keyboard").Jump).toContainMatch("Space")
			client.runtime.services.UserInputService.LastInputTypeChanged:Fire(Enum.UserInputType.Gamepad1)
			game.step(2)
			expect(input.getPlatform()).toBe("Gamepad")
			expect(input.getBindingLabels().Super).toBe("RB / RT")
			expect(input.getBindingLabels().Light).toBe("X")
			expect(game.errors()).toBeEmpty()
		end
	)
end)
