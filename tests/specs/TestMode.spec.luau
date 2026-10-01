describe("Temporary roster testing", function()
	it("opens every menu slot before receiving a profile and after a stale profile", function()
		local runtime = newRuntime({ isClient = true })
		local loader = newLoader({
			globals = runtime.globals,
			services = runtime.services,
			overrides = { ["src/shared/Config/TestMode.luau"] = { UnlockAllCharacters = true } },
		})
		local Fusion = loader.require(loader.get("ReplicatedStorage", "Packages", "Fusion"))
		local AppState = loader.require(loader.get("StarterPlayer", "StarterPlayerScripts", "Client", "UI", "AppState"))
		local scope = Fusion.scoped(Fusion)
		local state = AppState.new(scope)
		local Registry = requireShared("Characters", "CharacterRegistry")
		for _, def in Registry.list() do
			expect(Fusion.peek(state.ownedCharacters)[def.id]).toBe(true)
		end
		AppState.applyProfile(state, { ownedCharacters = { rook = true } })
		for _, def in Registry.list() do
			expect(Fusion.peek(state.ownedCharacters)[def.id]).toBe(true)
		end
		scope:doCleanup()
	end)
	it("opens all 16 fighters in the UI and server without saving purchases", function()
		local config = { UnlockAllCharacters = true }
		local game = Harness.new({ overrides = { ["src/shared/Config/TestMode.luau"] = config } })
		local client = game.addClient("Tester")
		game.step(2)
		local Data = game.serverRequire("Services", "DataService")
		local Registry = requireShared("Characters", "CharacterRegistry")
		for _, def in Registry.list() do
			expect(Data.ownsCharacter(client.player, def.id)).toBe(true)
		end
		expect(Data.get(client.player).ownedCharacters).toBeEmpty()
		client.click("Персонажи")
		game.step(2)
		client.runtime.fire(client.find("Roster"):FindFirstChild("ashka"), "Activated")
		game.step(2)
		client.click("Выбрать")
		game.step(2)
		client.click("← Назад")
		game.step(2)
		client.click("Тренировка")
		game.step(4)
		expect(client.find("Battle") ~= nil).toBeTruthy()
		expect(Data.get(client.player).ownedCharacters).toBeEmpty()
		config.UnlockAllCharacters = false
		expect(Data.ownsCharacter(client.player, "ashka")).toBe(false)
		expect(Data.ownsCharacter(client.player, "rook")).toBe(true)
		expect(game.errors()).toBeEmpty()
	end)
end)
