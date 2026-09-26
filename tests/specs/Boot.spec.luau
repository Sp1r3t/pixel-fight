-- Смоук-тесты: запуск сервера и клиента, навигация по меню на Fusion.
-- Инстансы создаются через @lune/roblox, поэтому неверное имя/тип свойства = падение теста.

local function expectHealthy(game)
	expect(game.errors()).toBeEmpty()
	expect(game.warnings()).toBeEmpty()
end

local function boot(options)
	local game = Harness.new(options)
	local client = game.addClient("Alice")
	game.step(2)
	return game, client
end

describe("Сервер", function()
	it(
		"запускается: конфиг валиден, все сервисы проходят Init/Start",
		function()
			local game = Harness.new()
			game.step(2)
			expectHealthy(game)
		end
	)
end)

describe("Клиент", function()
	it("запускается и монтирует главное меню", function()
		local game, client = boot()
		expectHealthy(game)
		expect(client.gui() ~= nil).toBeTruthy()
		expect(client.find("MainMenu") ~= nil).toBeTruthy()
	end)

	it(
		"из главного меню открывается каждый раздел и возвращается назад",
		function()
			local game, client = boot()
			local sections = {
				{ button = "Одиночная игра", screen = "BossMap" },
				{ button = "Мультиплеер", screen = "ModeSelect" },
				{ button = "Персонажи", screen = "CharacterSelect" },
				{ button = "Магазин", screen = "PlaceholderScreen" },
				{ button = "Управление", screen = "ControlsSettings" },
			}
			for _, section in sections do
				client.click(section.button)
				game.step(2)
				expect(client.find(section.screen) ~= nil).toBeTruthy()
				expect(client.find("MainMenu")).toBe(nil)
				client.click("← Назад")
				game.step(2)
				expect(client.find("MainMenu") ~= nil).toBeTruthy()
			end
			expectHealthy(game)
		end
	)

	it(
		"выбор персонажа: 16 карточек, детали, выбор бесплатного, платный заблокирован",
		function()
			local game, client = boot()
			local runtime = client.runtime
			client.click("Персонажи")
			game.step(2)

			local roster = client.find("Roster")
			local cards = 0
			for _, child in roster:GetChildren() do
				if child:IsA("TextButton") then
					cards += 1
				end
			end
			expect(cards).toBe(16)

			-- Бесплатный персонаж: можно выбрать.
			runtime.fire(runtime.findByName(roster, "mira"), "Activated")
			game.step(2)
			expect(client.findText("MIRA VOSS", "TextLabel") ~= nil).toBeTruthy()
			client.click("Выбрать")
			game.step(2)
			expect(client.findText("Выбран") ~= nil).toBeTruthy()
			expect(runtime.findByName(runtime.findByName(roster, "mira"), "ChosenMark").Visible).toBe(true)
			expect(runtime.findByName(runtime.findByName(roster, "rook"), "ChosenMark").Visible).toBe(false)

			-- Платный персонаж: покупка появится на этапе 9, кнопка неактивна.
			runtime.fire(runtime.findByName(roster, "ashka"), "Activated")
			game.step(2)
			expect(client.findText("ASHKA", "TextLabel") ~= nil).toBeTruthy()
			client.click("Купить (этап 9)")
			game.step(2)
			expect(runtime.findByName(runtime.findByName(roster, "ashka"), "ChosenMark").Visible).toBe(false)

			-- Выбор отражается в главном меню.
			client.click("← Назад")
			game.step(2)
			expect(client.findText("MIRA VOSS", "TextLabel") ~= nil).toBeTruthy()

			-- Анимации (пружины, твины, переливающиеся рамки Deluxe) отрабатывают без ошибок.
			game.step(120)
			expectHealthy(game)
		end
	)

	it("масштабируется под экран телефона", function()
		local game, client = boot({ screenSize = Vector2.new(844, 390) })
		local scale = client.runtime.findByName(client.find("Root"), "UIScale")
		expect(scale.Scale).toBeCloseTo(390 / 540, 1e-4)
		expectHealthy(game)
	end)
end)
