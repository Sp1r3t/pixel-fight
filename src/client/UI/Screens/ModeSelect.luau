--!strict
--[[
	Экран «Мультиплеер» — выбор режима.
	  • Онлайн: быстрый бой 1 на 1 и команды 2 на 2 (эстафета) — поиск соперников в очереди;
	  • С другом: приватная комната 1 на 1 или 2 на 2 с кодом; вход по коду друга;
	  • Против компьютера: четыре уровня сложности (ИИ боссов).
	Пока идёт поиск или открыта комната — поверх экрана панель статуса (таймер, код, участники, отмена).
	Все данные — Fusion Values из AppState (статус очереди присылает сервер).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local ScreenHeader = require(script.Parent.Parent.Components.ScreenHeader)

local Children, Out, peek = Fusion.Children, Fusion.Out, Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>

local MODE_NAMES: { [string]: string } = {
	Versus = "1 на 1",
	Team = "2 на 2",
}

local CPU_LEVELS: { { level: number, text: string } } = {
	{ level = 3, text = "Лёгкий" },
	{ level = 8, text = "Средний" },
	{ level = 13, text = "Сложный" },
	{ level = 18, text = "Мастер" },
}

local function Title(scope: Scope, text: string, position: UDim2): Instance
	return scope:New "TextLabel" {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Position = position,
		Size = UDim2.fromOffset(400, 26),
		Text = text,
		TextColor3 = Theme.Colors.Accent,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
end

local function Hint(scope: Scope, text: string, position: UDim2, height: number): Instance
	return scope:New "TextLabel" {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.BodyRegular,
		Position = position,
		Size = UDim2.fromOffset(400, height),
		Text = text,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}
end

local function Panel(scope: Scope, name: string, position: UDim2, size: UDim2, children: { Fusion.Child }): Instance
	return scope:New "Frame" {
		Name = name,
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
		[Children] = {
			scope:New "UIStroke" {
				Color = Theme.Colors.Outline,
				Thickness = Theme.Outline,
			},
			children,
		} :: { Fusion.Child },
	}
end

-- Панель статуса поиска/комнаты поверх экрана.
local function StatusOverlay(scope: Scope, state: AppState.AppState, now: Fusion.Value<number>): Instance
	local status = scope:Computed(function(use)
		return use(state.queue).status
	end)

	local headline = scope:Computed(function(use)
		local queue = use(state.queue)
		local mode = MODE_NAMES[queue.mode or ""] or ""
		if queue.status == "Searching" then
			local seconds = math.max(0, math.floor(use(now) - queue.since))
			return `Поиск соперников ({mode})  {seconds // 60}:{string.format("%02d", seconds % 60)}`
		elseif queue.status == "Room" then
			return `Комната {mode}: код`
		elseif queue.status == "Teleporting" then
			return "Соперники найдены! Подключение к серверу матча…"
		elseif queue.status == "Found" then
			return "Соперники найдены!"
		end
		return ""
	end)

	local details = scope:Computed(function(use)
		local queue = use(state.queue)
		if queue.status == "Searching" then
			return if queue.mode == "Team"
				then "Нужно 4 игрока. Команды формируются автоматически."
				else "Ищем соперника на этом и других серверах."
		elseif queue.status == "Room" then
			local names: { string } = {}
			local members: { { name: string, characterId: string } } = queue.members or {}
			for _, member in members do
				local def = CharacterRegistry.get(member.characterId)
				table.insert(names, `{member.name} ({if def then def.displayName else member.characterId})`)
			end
			local capacity = queue.capacity or 2
			local teamsHint = if queue.mode == "Team"
				then " Команды: 1-й и 3-й против 2-го и 4-го."
				else ""
			return `Игроки {#names}/{capacity}: {table.concat(names, ", ")}. Скажите код другу — бой начнётся, `
				.. `когда все войдут.{teamsHint}`
		end
		return ""
	end)

	return scope:New "Frame" {
		Name = "QueueStatus",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Colors.BackgroundAlt,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(560, 250),
		Visible = scope:Computed(function(use)
			return use(status) ~= "Idle"
		end),
		ZIndex = 20,
		[Children] = {
			scope:New "UIStroke" {
				Color = Theme.Colors.Accent,
				Thickness = Theme.Outline,
			},
			scope:New "TextLabel" {
				Name = "Headline",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.fromOffset(20, 18),
				Size = UDim2.fromOffset(520, 30),
				Text = headline,
				TextColor3 = Theme.Colors.Text,
				TextSize = 22,
				TextWrapped = true,
				ZIndex = 21,
			},
			scope:New "TextLabel" {
				Name = "RoomCode",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.fromOffset(20, 52),
				Size = UDim2.fromOffset(520, 56),
				Text = scope:Computed(function(use)
					return use(state.queue).code or ""
				end),
				TextColor3 = Theme.Colors.Accent,
				TextSize = 56,
				Visible = scope:Computed(function(use)
					return use(status) == "Room"
				end),
				ZIndex = 21,
			},
			scope:New "TextLabel" {
				Name = "Details",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.BodyRegular,
				Position = UDim2.fromOffset(20, 116),
				Size = UDim2.fromOffset(520, 66),
				Text = details,
				TextColor3 = Theme.Colors.TextDim,
				TextSize = 15,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 21,
			},
			Button(scope, {
				Name = "CancelQueue",
				Text = scope:Computed(function(use)
					return if use(status) == "Room" then "Выйти из комнаты" else "Отмена"
				end),
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 190),
				Size = UDim2.fromOffset(240, 44),
				Disabled = scope:Computed(function(use)
					local current = use(status)
					return current == "Teleporting" or current == "Found"
				end),
				OnClick = function()
					if peek(state.queue).status == "Room" then
						state.actions.leaveRoom()
					else
						state.actions.leaveQueue()
					end
				end,
			}),
		} :: { Fusion.Child },
	}
end

local function ModeSelect(scope: Scope, state: AppState.AppState): Instance
	-- «Часы» для таймера поиска; соединение удаляется вместе со scope экрана.
	local now = scope:Value(os.clock())
	table.insert(
		scope,
		RunService.RenderStepped:Connect(function()
			now:set(os.clock())
		end)
	)
	local codeText = scope:Value("")

	local cpuButtons: { Instance } = {}
	for index, entry in CPU_LEVELS do
		table.insert(
			cpuButtons,
			Button(scope, {
				Name = `Cpu{entry.level}`,
				Text = entry.text,
				Position = UDim2.fromOffset(20 + (index - 1) * 216, 44),
				Size = UDim2.fromOffset(200, 44),
				TextSize = 18,
				OnClick = function()
					state.actions.startCpu(entry.level)
				end,
			})
		)
	end

	local fighterName = scope:Computed(function(use)
		local def = CharacterRegistry.get(use(state.selectedCharacterId))
		return `Ваш боец: {if def then def.displayName else "?"}`
	end)

	return scope:New "Frame" {
		Name = "ModeSelect",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			ScreenHeader(scope, {
				Title = "МУЛЬТИПЛЕЕР",
				OnBack = function()
					-- Уходя с экрана, не держим игрока в очереди.
					local queue = peek(state.queue)
					if queue.status == "Searching" then
						state.actions.leaveQueue()
					elseif queue.status == "Room" then
						state.actions.leaveRoom()
					end
					AppState.back(state)
				end,
			}),
			scope:New "TextLabel" {
				Name = "Fighter",
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.new(1, -150, 0, 20),
				Size = UDim2.fromOffset(200, 28),
				Text = fighterName,
				TextColor3 = Theme.Colors.Text,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Right,
			},
			Button(scope, {
				Name = "ChangeFighter",
				Text = "Сменить",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -20, 0, 16),
				Size = UDim2.fromOffset(120, 36),
				TextSize = 16,
				OnClick = function()
					AppState.navigate(state, "CharacterSelect")
				end,
			}),
			Panel(scope, "Online", UDim2.fromOffset(24, 76), UDim2.fromOffset(440, 290), {
				Title(scope, "Онлайн", UDim2.fromOffset(20, 12)),
				Button(scope, {
					Name = "QueueVersus",
					Text = "Быстрый бой 1 на 1",
					Color = Theme.Colors.ButtonPrimary,
					Position = UDim2.fromOffset(20, 48),
					Size = UDim2.fromOffset(400, 48),
					OnClick = function()
						state.actions.joinQueue("Versus")
					end,
				}),
				Button(scope, {
					Name = "QueueTeam",
					Text = "Команды 2 на 2",
					Position = UDim2.fromOffset(20, 108),
					Size = UDim2.fromOffset(400, 48),
					OnClick = function()
						state.actions.joinQueue("Team")
					end,
				}),
				Hint(
					scope,
					`До {GameConfig.RoundsToWin.Versus} побед в раундах. 2 на 2 — эстафета: на арене всегда один `
						.. "на один; выбывшего сменяет напарник, победитель дуэли остаётся с текущим здоровьем. "
						.. `Победа в онлайн-бою: +{GameConfig.Matchmaking.WinReward} монет.`,
					UDim2.fromOffset(20, 170),
					100
				),
			}),
			Panel(scope, "Friends", UDim2.fromOffset(496, 76), UDim2.fromOffset(440, 290), {
				Title(scope, "С другом", UDim2.fromOffset(20, 12)),
				Button(scope, {
					Name = "RoomVersus",
					Text = "Комната 1 на 1",
					Position = UDim2.fromOffset(20, 48),
					Size = UDim2.fromOffset(194, 48),
					TextSize = 18,
					OnClick = function()
						state.actions.createRoom("Versus")
					end,
				}),
				Button(scope, {
					Name = "RoomTeam",
					Text = "Комната 2 на 2",
					Position = UDim2.fromOffset(226, 48),
					Size = UDim2.fromOffset(194, 48),
					TextSize = 18,
					OnClick = function()
						state.actions.createRoom("Team")
					end,
				}),
				scope:New "TextBox" {
					Name = "CodeInput",
					BackgroundColor3 = Theme.Colors.PanelLight,
					BorderSizePixel = 0,
					ClearTextOnFocus = false,
					Font = Theme.Fonts.Pixel,
					PlaceholderColor3 = Theme.Colors.TextDim,
					PlaceholderText = "КОД",
					Position = UDim2.fromOffset(20, 116),
					Size = UDim2.fromOffset(250, 48),
					Text = "",
					TextColor3 = Theme.Colors.Text,
					TextSize = 30,
					[Out "Text"] = codeText,
				},
				Button(scope, {
					Name = "JoinRoom",
					Text = "Войти",
					Color = Theme.Colors.ButtonPrimary,
					Position = UDim2.fromOffset(282, 116),
					Size = UDim2.fromOffset(138, 48),
					OnClick = function()
						state.actions.joinRoom(peek(codeText))
					end,
				}),
				Hint(
					scope,
					"Создайте комнату и продиктуйте код другу — или введите код, который дал вам друг. "
						.. "Друг может быть на другом сервере: вас перенесёт к нему автоматически.",
					UDim2.fromOffset(20, 178),
					90
				),
			}),
			Panel(scope, "Cpu", UDim2.fromOffset(24, 380), UDim2.fromOffset(912, 110), {
				Title(scope, "Против компьютера", UDim2.fromOffset(20, 10)),
				cpuButtons,
			}),
			StatusOverlay(scope, state, now),
		} :: { Fusion.Child },
	}
end

return ModeSelect
