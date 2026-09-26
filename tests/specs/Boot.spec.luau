-- Смоук-тесты: запуск сервера и клиента, навигация по меню на Fusion.
-- Инстансы создаются через @lune/roblox, поэтому неверное имя/тип свойства = падение теста.

local function bootClient(screenSize)
	local runtime = newRuntime({ isClient = true, screenSize = screenSize })
	local loader = newLoader({ globals = runtime.globals, services = runtime.services })
	loader.run(loader.get("StarterPlayer", "StarterPlayerScripts", "Client"))
	runtime.step(2)
	local playerGui = runtime.localPlayer:FindFirstChild("PlayerGui")
	return runtime, playerGui
end

local function expectHealthy(runtime)
	expect(runtime.errors).toBeEmpty()
	expect(runtime.warnings).toBeEmpty()
end

local function click(runtime, root, text)
	local button = runtime.findGuiByText(root, text)
	assert(button, `кнопка "{text}" не найдена`)
	runtime.fire(button, "Activated")
	runtime.step(2)
end

describe("Сервер", function()
	it(
		"запускается: конфиг валиден, все сервисы проходят Init/Start",
		function()
			local runtime = newRuntime({ isClient = false })
			local loader = newLoader({ globals = runtime.globals, services = runtime.services })
			loader.run(loader.get("ServerScriptService", "Server"))
			expectHealthy(runtime)
		end
	)
end)

describe("Клиент", function()
	it("запускается и монтирует главное меню", function()
		local runtime, playerGui = bootClient()
		expectHealthy(runtime)
		local gui = playerGui:FindFirstChild("PixelFightUI")
		expect(gui ~= nil).toBeTruthy()
		expect(runtime.findByName(gui, "MainMenu") ~= nil).toBeTruthy()
	end)

	it(
		"из главного меню открывается каждый раздел и возвращается назад",
		function()
			local runtime, playerGui = bootClient()
			local gui = playerGui:FindFirstChild("PixelFightUI")
			local sections = {
				{ button = "Одиночная игра", screen = "PlaceholderScreen" },
				{ button = "Мультиплеер", screen = "PlaceholderScreen" },
				{ button = "Персонажи", screen = "CharacterSelect" },
				{ button = "Магазин", screen = "PlaceholderScreen" },
				{ button = "Управление", screen = "PlaceholderScreen" },
			}
			for _, section in sections do
				click(runtime, gui, section.button)
				expect(runtime.findByName(gui, section.screen) ~= nil).toBeTruthy()
				expect(runtime.findByName(gui, "MainMenu")).toBe(nil)
				click(runtime, gui, "← Назад")
				expect(runtime.findByName(gui, "MainMenu") ~= nil).toBeTruthy()
			end
			expectHealthy(runtime)
		end
	)

	it(
		"выбор персонажа: 16 карточек, детали, выбор бесплатного, платный заблокирован",
		function()
			local runtime, playerGui = bootClient()
			local gui = playerGui:FindFirstChild("PixelFightUI")
			click(runtime, gui, "Персонажи")

			local roster = runtime.findByName(gui, "Roster")
			local cards = 0
			for _, child in roster:GetChildren() do
				if child:IsA("TextButton") then
					cards += 1
				end
			end
			expect(cards).toBe(16)

			-- Бесплатный персонаж: можно выбрать.
			runtime.fire(runtime.findByName(roster, "mira"), "Activated")
			runtime.step(2)
			expect(runtime.findGuiByText(gui, "MIRA VOSS", "TextLabel") ~= nil).toBeTruthy()
			click(runtime, gui, "Выбрать")
			expect(runtime.findGuiByText(gui, "Выбран") ~= nil).toBeTruthy()
			expect(runtime.findByName(runtime.findByName(roster, "mira"), "ChosenMark").Visible).toBe(true)
			expect(runtime.findByName(runtime.findByName(roster, "rook"), "ChosenMark").Visible).toBe(false)

			-- Платный персонаж: покупка появится на этапе 9, кнопка неактивна.
			runtime.fire(runtime.findByName(roster, "ashka"), "Activated")
			runtime.step(2)
			expect(runtime.findGuiByText(gui, "ASHKA", "TextLabel") ~= nil).toBeTruthy()
			click(runtime, gui, "Купить (этап 9)")
			expect(runtime.findByName(runtime.findByName(roster, "ashka"), "ChosenMark").Visible).toBe(false)

			-- Выбор отражается в главном меню.
			click(runtime, gui, "← Назад")
			expect(runtime.findGuiByText(gui, "MIRA VOSS", "TextLabel") ~= nil).toBeTruthy()

			-- Анимации (пружины, твины, переливающиеся рамки Deluxe) отрабатывают без ошибок.
			runtime.step(120)
			expectHealthy(runtime)
		end
	)

	it("масштабируется под экран телефона", function()
		local runtime, playerGui = bootClient(Vector2.new(844, 390))
		local gui = playerGui:FindFirstChild("PixelFightUI")
		local scale = runtime.findByName(runtime.findByName(gui, "Root"), "UIScale")
		expect(scale.Scale).toBeCloseTo(390 / 540, 1e-4)
		expectHealthy(runtime)
	end)
end)
