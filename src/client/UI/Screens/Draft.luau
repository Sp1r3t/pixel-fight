--!strict
--[[
	Экран «Подготовка к бою» (мультиплеер и бой с компьютером):
	  1. «Выбери бойца» — сетка бойцов (закрытые затемнены), кнопка «ГОТОВ!»;
	  2. «Выбери карту» — 10 карточек карт с картинкой и голосами; премиальную карту может выбрать
	     только её владелец (замок и подсказка), а играют на ней все;
	  3. итог — большая картинка выбранной карты.
	Сверху — команды (слева синие, справа красные) с бойцами и готовностью, таймер фазы.
	Состояние присылает сервер (DraftService → AppState.draft); экран только отправляет выбор.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Arenas = require(ReplicatedStorage.Shared.Config.Arenas)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local FighterPortrait = require(script.Parent.Parent.Components.FighterPortrait)
local ArenaArt = require(script.Parent.Parent.Parent.Fight.ArenaArt)

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>

local TEAM_COLORS: { Color3 } = { Color3.fromHex("#4DB8FF"), Color3.fromHex("#FF5A6E") }
local LOCK_SHADE = Color3.fromHex("#05030B")

local PHASE_TITLES: { [string]: string } = {
	Character = "ВЫБЕРИ БОЙЦА",
	Map = "ВЫБЕРИ КАРТУ",
	Reveal = "КАРТА ВЫБРАНА!",
}

local function label(
	scope: Scope,
	props: {
		Name: string?,
		Text: Fusion.UsedAs<string>,
		Position: UDim2,
		Size: UDim2,
		TextSize: number,
		Color: Fusion.UsedAs<Color3>?,
		Font: Enum.Font?,
		Align: Enum.TextXAlignment?,
		ZIndex: number?,
	}
): Instance
	return scope:New "TextLabel" {
		Name = props.Name or "Label",
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Body,
		Position = props.Position,
		Size = props.Size,
		Text = props.Text,
		TextColor3 = props.Color or Theme.Colors.Text,
		TextSize = props.TextSize,
		TextStrokeTransparency = 0.5,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = props.Align or Enum.TextXAlignment.Center,
		ZIndex = props.ZIndex or 1,
	}
end

-- Карточка участника вверху: портрет выбранного бойца, имя игрока, боец, готовность / голос.
local function SlotCard(scope: Scope, slot: AppState.DraftSlotInfo, info: AppState.DraftInfo, x: number): Instance
	local def = CharacterRegistry.get(slot.characterId)
	local isLocal = slot.slot == info.localSlot
	local status = ""
	if info.phase == "Character" then
		status = if slot.ready then "✓ Готов" else "Выбирает…"
	else
		local arena = if slot.vote then Arenas.byId[slot.vote] else nil
		status = if arena then arena.name elseif slot.bot then "" else "Голосует…"
	end
	local portrait: { Instance } = {}
	if def then
		table.insert(
			portrait,
			FighterPortrait(scope, {
				Character = def,
				Framing = "Bust",
				Facing = if slot.team == 1 then 1 else -1,
				Size = UDim2.fromOffset(60, 60),
				Position = UDim2.fromOffset(6, 6),
			})
		)
	end
	return scope:New "Frame" {
		Name = `Slot{slot.slot}`,
		BackgroundColor3 = Theme.Colors.Panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, 72),
		Size = UDim2.fromOffset(214, 72),
		[Children] = {
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = if isLocal then Theme.Colors.Accent else TEAM_COLORS[slot.team],
				Thickness = if isLocal then 4 else 2,
			},
			portrait,
			label(scope, {
				Name = "Player",
				Text = if isLocal then "ВЫ" else slot.name,
				Position = UDim2.fromOffset(72, 6),
				Size = UDim2.fromOffset(136, 20),
				TextSize = 17,
				Color = TEAM_COLORS[slot.team],
				Align = Enum.TextXAlignment.Left,
			}),
			label(scope, {
				Name = "Fighter",
				Text = string.upper(if def then def.displayName else slot.characterId),
				Font = Theme.Fonts.Pixel,
				Position = UDim2.fromOffset(72, 26),
				Size = UDim2.fromOffset(136, 20),
				TextSize = 18,
				Align = Enum.TextXAlignment.Left,
			}),
			label(scope, {
				Name = "Status",
				Text = status,
				Position = UDim2.fromOffset(72, 47),
				Size = UDim2.fromOffset(136, 18),
				TextSize = 14,
				Color = if (info.phase == "Character" and slot.ready) or (info.phase ~= "Character" and slot.vote)
					then Theme.Colors.Free
					else Theme.Colors.TextDim,
				Align = Enum.TextXAlignment.Left,
			}),
		} :: { Fusion.Child },
	}
end

local function TeamsRow(scope: Scope, state: AppState.AppState): Fusion.Child
	return scope:Computed(function(use, innerScope: Scope): { Instance }
		local info = use(state.draft)
		local items: { Instance } = {}
		if info == nil then
			return items
		end
		local counts = { 0, 0 }
		for _, slot in info.slots do
			local team = slot.team
			counts[team] += 1
			local index = counts[team]
			-- Синие слева от центра, красные справа; «VS» посередине.
			local x = if team == 1 then 480 - 40 - index * 222 + 8 else 480 + 40 + (index - 1) * 222
			table.insert(items, SlotCard(innerScope, slot, info, x))
		end
		table.insert(
			items,
			label(innerScope, {
				Name = "Versus",
				Text = "VS",
				Font = Theme.Fonts.Pixel,
				Position = UDim2.fromOffset(440, 88),
				Size = UDim2.fromOffset(80, 40),
				TextSize = 40,
				Color = Theme.Colors.Accent,
			})
		)
		return items
	end)
end

----------------------------------------------------------------------------------------------
-- Фаза 1: бойцы
----------------------------------------------------------------------------------------------

local function CharacterPhase(scope: Scope, state: AppState.AppState): Instance
	local mine = scope:Computed(function(use): AppState.DraftSlotInfo?
		local info = use(state.draft)
		return if info then AppState.draftSlot(info) else nil
	end)
	local ready = scope:Computed(function(use)
		local slot = use(mine)
		return slot ~= nil and slot.ready
	end)
	local chosen = scope:Computed(function(use)
		local slot = use(mine)
		return if slot then slot.characterId else ""
	end)

	local cards: { Instance } = {}
	for _, def in CharacterRegistry.list() do
		local owned = scope:Computed(function(use)
			return use(state.ownedCharacters)[def.id] == true
		end)
		local isChosen = scope:Computed(function(use)
			return use(chosen) == def.id
		end)
		table.insert(
			cards,
			scope:New "TextButton" {
				Name = `Pick_{def.id}`,
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Colors.PanelLight,
				BorderSizePixel = 0,
				LayoutOrder = def.order,
				Text = "",
				[OnEvent "Activated"] = function()
					if peek(owned) and not peek(ready) then
						state.selectedCharacterId:set(def.id)
						state.actions.draftPick(def.id)
					end
				end,
				[Children] = {
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = scope:Computed(function(use)
							return if use(isChosen) then Theme.Colors.Accent else Color3.fromHex(def.palette.accent)
						end),
						Thickness = scope:Computed(function(use)
							return if use(isChosen) then 4 else 1
						end),
					},
					FighterPortrait(scope, {
						Character = def,
						Framing = "Bust",
						Size = UDim2.fromOffset(62, 62),
						Position = UDim2.new(0.5, 0, 0, 4),
						AnchorPoint = Vector2.new(0.5, 0),
					}),
					scope:New "TextLabel" {
						Name = "Name",
						BackgroundTransparency = 1,
						Font = Theme.Fonts.Pixel,
						Position = UDim2.new(0, 3, 1, -20),
						Size = UDim2.new(1, -6, 0, 17),
						Text = string.upper(def.displayName),
						TextColor3 = Theme.Colors.Text,
						TextScaled = true,
						TextStrokeTransparency = 0.5,
						[Children] = scope:New "UITextSizeConstraint" {
							MaxTextSize = 15,
						},
					},
					scope:New "TextLabel" {
						Name = "Locked",
						BackgroundColor3 = LOCK_SHADE,
						BackgroundTransparency = 0.45,
						BorderSizePixel = 0,
						Font = Theme.Fonts.Body,
						Size = UDim2.fromScale(1, 1),
						Text = "🔒",
						TextSize = 26,
						TextColor3 = Theme.Colors.Text,
						Visible = scope:Computed(function(use)
							return not use(owned)
						end),
						ZIndex = 3,
					},
				} :: { Fusion.Child },
			}
		)
	end

	local info = scope:Computed(function(use): string
		local def = CharacterRegistry.get(use(chosen))
		if def == nil then
			return ""
		end
		return `{def.title} · Особый: {def.special.move.name} · Супер: {def.super.move.name}`
	end)

	return scope:New "Frame" {
		Name = "CharacterPhase",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			scope:New "Frame" {
				Name = "Roster",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(92, 156),
				Size = UDim2.fromOffset(776, 188),
				[Children] = {
					scope:New "UIGridLayout" {
						CellPadding = UDim2.fromOffset(8, 8),
						CellSize = UDim2.fromOffset(90, 90),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					cards,
				} :: { Fusion.Child },
			},
			label(scope, {
				Name = "FighterInfo",
				Text = scope:Computed(function(use)
					local def = CharacterRegistry.get(use(chosen))
					return if def then string.upper(def.displayName) else ""
				end),
				Font = Theme.Fonts.Pixel,
				Position = UDim2.fromOffset(80, 352),
				Size = UDim2.fromOffset(800, 30),
				TextSize = 30,
				Color = Theme.Colors.Accent,
			}),
			label(scope, {
				Name = "FighterMoves",
				Text = info,
				Position = UDim2.fromOffset(80, 384),
				Size = UDim2.fromOffset(800, 22),
				TextSize = 16,
				Color = Theme.Colors.TextDim,
			}),
			Button(scope, {
				Name = "DraftReady",
				Text = scope:Computed(function(use)
					return if use(ready) then "Ждём остальных…" else "ГОТОВ!"
				end),
				Color = Theme.Colors.ButtonPrimary,
				Disabled = ready,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 420),
				Size = UDim2.fromOffset(300, 60),
				TextSize = 26,
				OnClick = function()
					state.actions.draftReady()
				end,
			}),
			label(scope, {
				Name = "Hint",
				Text = "Закрытых бойцов можно открыть в магазине — за монеты или Robux.",
				Position = UDim2.fromOffset(80, 492),
				Size = UDim2.fromOffset(800, 20),
				TextSize = 14,
				Color = Theme.Colors.TextDim,
			}),
		} :: { Fusion.Child },
	}
end

----------------------------------------------------------------------------------------------
-- Фаза 2: карта
----------------------------------------------------------------------------------------------

local function MapCard(scope: Scope, state: AppState.AppState, arena: Arenas.ArenaTheme, index: number): Instance
	local owned = scope:Computed(function(use)
		return use(state.ownedArenas)[arena.id] == true
	end)
	local myVote = scope:Computed(function(use): string?
		local info = use(state.draft)
		local slot = if info then AppState.draftSlot(info) else nil
		return if slot then slot.vote else nil
	end)
	local votes = scope:Computed(function(use): number
		local info = use(state.draft)
		return if info then info.votes[arena.id] or 0 else 0
	end)
	local column, row = (index - 1) % 5, (index - 1) // 5
	local picture = scope:New "Frame" {
		Name = "Picture",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, 92),
	}
	ArenaArt.preview(picture, arena)
	local badges: { Instance } = {}
	if arena.premium then
		table.insert(
			badges,
			scope:New "TextLabel" {
				Name = "Premium",
				BackgroundColor3 = Theme.Colors.Paid,
				BorderSizePixel = 0,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.fromOffset(74, 18),
				Text = "👑 PREMIUM",
				TextColor3 = Theme.Colors.Outline,
				TextSize = 13,
				ZIndex = 4,
			}
		)
	end

	return scope:New "TextButton" {
		Name = `Map_{arena.id}`,
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.Panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(40 + column * 178, 156 + row * 132),
		Size = UDim2.fromOffset(170, 122),
		Text = "",
		[OnEvent "Activated"] = function()
			if peek(owned) then
				state.actions.draftVote(arena.id)
			else
				AppState.notify(
					state,
					"Эту карту выбирает только её владелец. Открой её в магазине!",
					3
				)
			end
		end,
		[Children] = {
			picture,
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = scope:Computed(function(use)
					if use(myVote) == arena.id then
						return Theme.Colors.Accent
					end
					return if arena.premium then Theme.Colors.Paid else Theme.Colors.Outline
				end),
				Thickness = scope:Computed(function(use)
					return if use(myVote) == arena.id then 5 else 2
				end),
			},
			label(scope, {
				Name = "MapName",
				Text = arena.name,
				Position = UDim2.fromOffset(4, 94),
				Size = UDim2.fromOffset(162, 24),
				TextSize = 15,
			}),
			badges,
			scope:New "TextLabel" {
				Name = "Votes",
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = Theme.Colors.Accent,
				BorderSizePixel = 0,
				Font = Theme.Fonts.Body,
				Position = UDim2.new(1, -4, 0, 4),
				Size = UDim2.fromOffset(44, 22),
				Text = scope:Computed(function(use)
					return `★ {use(votes)}`
				end),
				TextColor3 = Theme.Colors.Outline,
				TextSize = 15,
				Visible = scope:Computed(function(use)
					return use(votes) > 0
				end),
				ZIndex = 4,
			},
			scope:New "TextLabel" {
				Name = "Locked",
				BackgroundColor3 = LOCK_SHADE,
				BackgroundTransparency = 0.4,
				BorderSizePixel = 0,
				Font = Theme.Fonts.Body,
				Size = UDim2.new(1, 0, 0, 92),
				Text = "🔒\nТолько для владельцев",
				TextColor3 = Theme.Colors.Text,
				TextSize = 14,
				TextWrapped = true,
				Visible = scope:Computed(function(use)
					return not use(owned)
				end),
				ZIndex = 3,
			},
		} :: { Fusion.Child },
	}
end

local function MapPhase(scope: Scope, state: AppState.AppState): Instance
	local cards: { Instance } = {}
	for index, arena in Arenas.list do
		table.insert(cards, MapCard(scope, state, arena, index))
	end
	return scope:New "Frame" {
		Name = "MapPhase",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			cards,
			label(scope, {
				Name = "Hint",
				Text = "👑 Премиальную карту выбирает тот, кто её купил, — и если она победит, на ней играют все!",
				Position = UDim2.fromOffset(40, 424),
				Size = UDim2.fromOffset(880, 22),
				TextSize = 15,
				Color = Theme.Colors.Paid,
			}),
			label(scope, {
				Name = "Hint2",
				Text = "Больше голосов — та карта и будет. Ничья — выберет случай.",
				Position = UDim2.fromOffset(40, 450),
				Size = UDim2.fromOffset(880, 20),
				TextSize = 14,
				Color = Theme.Colors.TextDim,
			}),
		} :: { Fusion.Child },
	}
end

----------------------------------------------------------------------------------------------
-- Фаза 3: итог
----------------------------------------------------------------------------------------------

local function RevealPhase(scope: Scope, arenaId: string): Instance
	local arena = Arenas.byId[arenaId] or Arenas.byId[Arenas.default]
	local picture = scope:New "Frame" {
		Name = "ChosenMap",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.new(0.5, 0, 0, 160),
		Size = UDim2.fromOffset(448, 252),
		[Children] = scope:New "UIStroke" {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = if arena.premium then Theme.Colors.Paid else Theme.Colors.Accent,
			Thickness = 4,
		},
	}
	ArenaArt.preview(picture, arena)
	return scope:New "Frame" {
		Name = "RevealPhase",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			picture,
			label(scope, {
				Name = "ChosenName",
				Text = (if arena.premium then "👑 " else "") .. arena.name,
				Position = UDim2.fromOffset(80, 420),
				Size = UDim2.fromOffset(800, 36),
				TextSize = 30,
				Color = Theme.Colors.Accent,
			}),
			label(scope, {
				Name = "ChosenDescription",
				Text = arena.description,
				Position = UDim2.fromOffset(80, 458),
				Size = UDim2.fromOffset(800, 22),
				TextSize = 15,
				Color = Theme.Colors.TextDim,
			}),
		} :: { Fusion.Child },
	}
end

----------------------------------------------------------------------------------------------

local function Draft(scope: Scope, state: AppState.AppState): Instance
	local now = scope:Value(os.clock())
	table.insert(
		scope,
		RunService.RenderStepped:Connect(function()
			now:set(os.clock())
		end)
	)
	local phase = scope:Computed(function(use): string
		local info = use(state.draft)
		return if info then info.phase else "Character"
	end)
	local chosenArena = scope:Computed(function(use): string?
		local info = use(state.draft)
		return if info then info.arenaId else nil
	end)

	return scope:New "Frame" {
		Name = "Draft",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			Button(scope, {
				Name = "DraftLeave",
				Text = "← Выйти",
				Position = UDim2.fromOffset(16, 12),
				Size = UDim2.fromOffset(130, 42),
				TextSize = 20,
				OnClick = function()
					state.actions.draftLeave()
				end,
			}),
			label(scope, {
				Name = "Title",
				Text = scope:Computed(function(use)
					return PHASE_TITLES[use(phase)] or ""
				end),
				Position = UDim2.fromOffset(170, 12),
				Size = UDim2.fromOffset(620, 44),
				TextSize = 34,
				Color = Theme.Colors.Accent,
			}),
			scope:New "TextLabel" {
				Name = "Timer",
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = Theme.Colors.Panel,
				BorderSizePixel = 0,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.new(1, -16, 0, 10),
				Size = UDim2.fromOffset(70, 48),
				Text = scope:Computed(function(use)
					local info = use(state.draft)
					if info == nil then
						return ""
					end
					return tostring(math.max(0, math.ceil(info.deadline - use(now))))
				end),
				TextColor3 = scope:Computed(function(use)
					local info = use(state.draft)
					local left = if info then info.deadline - use(now) else 99
					return if left <= 5 then Color3.fromHex("#FF4D6D") else Theme.Colors.Text
				end),
				TextSize = 40,
				[Children] = scope:New "UIStroke" {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = Theme.Colors.Outline,
					Thickness = 3,
				},
			},
			TeamsRow(scope, state),
			scope:Computed(function(use, innerScope: Scope): Instance
				local current = use(phase)
				if current == "Map" then
					return MapPhase(innerScope, state)
				elseif current == "Reveal" then
					return RevealPhase(innerScope, use(chosenArena) or Arenas.default)
				end
				return CharacterPhase(innerScope, state)
			end),
		} :: { Fusion.Child },
	}
end

return Draft
