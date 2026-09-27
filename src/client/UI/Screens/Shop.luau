--!strict
--[[
	Экран «Магазин» — вкладки:
	  • «Бойцы»: 6 платных бойцов Deluxe — Game Pass за Robux или монеты, заработанные в игре;
	  • «Карты»: 3 премиальные карты — Game Pass или монеты; купленную карту можно выбрать
	    в голосовании перед боем, и тогда на ней играют все;
	  • «Монеты и боссы»: наборы монет и «Пропустить босса» (Developer Products).
	Покупку подтверждает сервер; экран только открывает окно покупки Roblox и показывает профиль.
	Платные бойцы не сильнее бесплатных — отличаются только внешним видом; карты — только фон.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Types = require(ReplicatedStorage.Shared.Types)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local BossRegistry = require(ReplicatedStorage.Shared.Characters.BossRegistry)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Arenas = require(ReplicatedStorage.Shared.Config.Arenas)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local PixelFigure = require(script.Parent.Parent.Components.PixelFigure)
local ScreenHeader = require(script.Parent.Parent.Components.ScreenHeader)
local ArenaArt = require(script.Parent.Parent.Parent.Fight.ArenaArt)

local Children, peek = Fusion.Children, Fusion.peek

local TABS: { { id: string, text: string } } = {
	{ id = "Fighters", text = "Бойцы" },
	{ id = "Maps", text = "Карты 👑" },
	{ id = "Coins", text = "Монеты и боссы" },
}

type Scope = Fusion.Scope<typeof(Fusion)>

local function Text(
	scope: Scope,
	props: {
		Name: string?,
		Text: Fusion.UsedAs<string>,
		Position: UDim2,
		Size: UDim2,
		TextSize: number?,
		Color: Color3?,
		Font: Enum.Font?,
		Align: Enum.TextXAlignment?,
		Visible: Fusion.UsedAs<boolean>?,
	}
): Instance
	return scope:New "TextLabel" {
		Name = props.Name or "Text",
		BackgroundTransparency = 1,
		Font = props.Font or Theme.Fonts.Body,
		Position = props.Position,
		Size = props.Size,
		Text = props.Text,
		TextColor3 = props.Color or Theme.Colors.Text,
		TextSize = props.TextSize or 16,
		TextWrapped = true,
		TextXAlignment = props.Align or Enum.TextXAlignment.Left,
		Visible = props.Visible or true,
	}
end

local function CharacterCard(scope: Scope, def: Types.CharacterDef, state: AppState.AppState): Instance
	local owned = scope:Computed(function(use)
		return use(state.ownedCharacters)[def.id] == true
	end)
	local price = Monetization.characterCoinPrice
	return scope:New "Frame" {
		Name = `Card_{def.id}`,
		BackgroundColor3 = Theme.Colors.PanelLight,
		BorderSizePixel = 0,
		LayoutOrder = def.order,
		[Children] = {
			scope:New "UIStroke" {
				Color = Color3.fromHex(def.palette.accent),
				Thickness = 2,
			},
			PixelFigure(scope, {
				Palette = def.palette,
				Size = UDim2.fromOffset(64, 64),
				Position = UDim2.fromOffset(6, 8),
			}),
			Text(scope, {
				Name = "CharacterName",
				Text = string.upper(def.displayName),
				Font = Theme.Fonts.Pixel,
				Position = UDim2.fromOffset(76, 8),
				Size = UDim2.fromOffset(170, 22),
				TextSize = 22,
			}),
			Text(scope, {
				Text = def.title,
				Position = UDim2.fromOffset(76, 30),
				Size = UDim2.fromOffset(170, 18),
				TextSize = 13,
				Color = Color3.fromHex(def.palette.accent),
			}),
			Text(scope, {
				Name = "Owned",
				Text = "✓ Открыт",
				Position = UDim2.fromOffset(76, 50),
				Size = UDim2.fromOffset(170, 22),
				Color = Theme.Colors.Free,
				Visible = owned,
			}),
			scope:New "Frame" {
				Name = "Buy",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(76, 52),
				Size = UDim2.new(1, -82, 0, 36),
				Visible = scope:Computed(function(use)
					return not use(owned)
				end),
				[Children] = {
					Button(scope, {
						Name = `Pass_{def.id}`,
						Text = `R$ {Monetization.gamePassPriceHint}`,
						Color = Theme.Colors.Paid,
						Size = UDim2.new(0.5, -3, 1, 0),
						TextSize = 16,
						OnClick = function()
							state.actions.promptPass(def.id)
						end,
					}),
					Button(scope, {
						Name = `Coins_{def.id}`,
						Text = `{price} мон.`,
						Position = UDim2.new(0.5, 3, 0, 0),
						Size = UDim2.new(0.5, -3, 1, 0),
						TextSize = 15,
						Disabled = scope:Computed(function(use)
							return use(state.coins) < price
						end),
						OnClick = function()
							state.actions.buyCharacter(def.id)
						end,
					}),
				} :: { Fusion.Child },
			},
		} :: { Fusion.Child },
	}
end

-- Карточка премиальной карты: большая картинка, описание, покупка.
local function MapCard(scope: Scope, arena: Arenas.ArenaTheme, index: number, state: AppState.AppState): Instance
	local owned = scope:Computed(function(use)
		return use(state.ownedArenas)[arena.id] == true
	end)
	local price = Monetization.arenaCoinPrice
	local picture = scope:New "Frame" {
		Name = "Picture",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(276, 155),
	}
	ArenaArt.preview(picture, arena)
	return scope:New "Frame" {
		Name = `Arena_{arena.id}`,
		BackgroundColor3 = Theme.Colors.PanelLight,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(24 + (index - 1) * 304, 0),
		Size = UDim2.fromOffset(292, 330),
		[Children] = {
			scope:New "UIStroke" {
				Color = Theme.Colors.Paid,
				Thickness = 3,
			},
			picture,
			Text(scope, {
				Name = "ArenaName",
				Text = `👑 {arena.name}`,
				Position = UDim2.fromOffset(10, 168),
				Size = UDim2.fromOffset(272, 26),
				TextSize = 20,
				Color = Theme.Colors.Paid,
			}),
			Text(scope, {
				Name = "ArenaDescription",
				Text = arena.description,
				Font = Theme.Fonts.BodyRegular,
				Position = UDim2.fromOffset(10, 196),
				Size = UDim2.fromOffset(272, 74),
				TextSize = 14,
				Color = Theme.Colors.TextDim,
			}),
			Text(scope, {
				Name = "Owned",
				Text = "✓ Открыта — выбирай в голосовании!",
				Position = UDim2.fromOffset(10, 284),
				Size = UDim2.fromOffset(272, 36),
				Color = Theme.Colors.Free,
				Visible = owned,
			}),
			scope:New "Frame" {
				Name = "Buy",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(8, 280),
				Size = UDim2.fromOffset(276, 42),
				Visible = scope:Computed(function(use)
					return not use(owned)
				end),
				[Children] = {
					Button(scope, {
						Name = `ArenaPass_{arena.id}`,
						Text = `R$ {Monetization.arenaPassPriceHint}`,
						Color = Theme.Colors.Paid,
						Size = UDim2.new(0.5, -3, 1, 0),
						TextSize = 17,
						OnClick = function()
							state.actions.promptArenaPass(arena.id)
						end,
					}),
					Button(scope, {
						Name = `ArenaCoins_{arena.id}`,
						Text = `{price} мон.`,
						Position = UDim2.new(0.5, 3, 0, 0),
						Size = UDim2.new(0.5, -3, 1, 0),
						TextSize = 16,
						Disabled = scope:Computed(function(use)
							return use(state.coins) < price
						end),
						OnClick = function()
							state.actions.buyArena(arena.id)
						end,
					}),
				} :: { Fusion.Child },
			},
		} :: { Fusion.Child },
	}
end

local function Shop(scope: Scope, state: AppState.AppState): Instance
	local tab = scope:Value("Fighters")
	local function visibleOn(id: string): Fusion.Computed<boolean>
		return scope:Computed(function(use)
			return use(tab) == id
		end)
	end
	local tabButtons: { Instance } = {}
	for index, entry in TABS do
		table.insert(
			tabButtons,
			Button(scope, {
				Name = `Tab_{entry.id}`,
				Text = entry.text,
				Color = scope:Computed(function(use)
					return if use(tab) == entry.id then Theme.Colors.ButtonPrimary else Theme.Colors.Button
				end),
				Position = UDim2.fromOffset(24 + (index - 1) * 208, 70),
				Size = UDim2.fromOffset(200, 40),
				TextSize = 18,
				OnClick = function()
					if peek(tab) ~= entry.id then
						tab:set(entry.id)
					end
				end,
			})
		)
	end
	local mapCards: { Instance } = {}
	local premiumIndex = 0
	for _, arena in Arenas.list do
		if arena.premium then
			premiumIndex += 1
			table.insert(mapCards, MapCard(scope, arena, premiumIndex, state))
		end
	end

	local cards: { Instance } = {}
	for _, def in CharacterRegistry.list() do
		if def.unlock == "Paid" then
			table.insert(cards, CharacterCard(scope, def, state))
		end
	end

	local productButtons: { Instance } = {}
	local y = 44
	for _, product in Monetization.products do
		if product.kind == "Coins" then
			table.insert(
				productButtons,
				Button(scope, {
					Name = `Product_{product.key}`,
					Text = `{product.name} — R$ {product.priceHint}`,
					Position = UDim2.fromOffset(16, y),
					Size = UDim2.fromOffset(268, 44),
					TextSize = 17,
					OnClick = function()
						state.actions.promptProduct(product.key)
					end,
				})
			)
			y += 52
		end
	end
	local skipPrice = 0
	for _, product in Monetization.products do
		if product.kind == "SkipBoss" then
			skipPrice = product.priceHint
		end
	end

	local nextBossText = scope:Computed(function(use)
		local progress = use(state.bossProgress)
		local boss = BossRegistry.byOrder(progress + 1)
		return if boss
			then `Следующий босс: {boss.order}. {boss.name}. Пропуск засчитывает победу (без награды).`
			else "Все боссы пройдены!"
	end)

	return scope:New "Frame" {
		Name = "Shop",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			ScreenHeader(scope, {
				Title = "МАГАЗИН",
				OnBack = function()
					AppState.back(state)
				end,
			}),
			Text(scope, {
				Name = "Coins",
				Text = scope:Computed(function(use)
					return `Монеты: {use(state.coins)}`
				end),
				Position = UDim2.new(1, -220, 0, 20),
				Size = UDim2.fromOffset(200, 24),
				Color = Theme.Colors.Accent,
				Align = Enum.TextXAlignment.Right,
				TextSize = 20,
			}),
			tabButtons,
			scope:New "Frame" {
				Name = "Maps",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 122),
				Size = UDim2.fromOffset(960, 400),
				Visible = visibleOn("Maps"),
				[Children] = {
					mapCards,
					Text(scope, {
						Name = "MapsHint",
						Text = "Премиальную карту в голосовании перед боем выбирает тот, кто её купил, — "
							.. "и если она победит, на ней играют все. На силу бойцов карты не влияют.",
						Font = Theme.Fonts.BodyRegular,
						Position = UDim2.fromOffset(24, 340),
						Size = UDim2.fromOffset(912, 44),
						TextSize = 14,
						Color = Theme.Colors.TextDim,
						Align = Enum.TextXAlignment.Center,
					}),
				} :: { Fusion.Child },
			},
			scope:New "Frame" {
				Name = "Deluxe",
				BackgroundColor3 = Theme.Colors.Panel,
				BorderSizePixel = 0,
				Position = UDim2.new(0.5, -294, 0, 122),
				Size = UDim2.fromOffset(588, 400),
				Visible = visibleOn("Fighters"),
				[Children] = {
					scope:New "UIStroke" {
						Color = Theme.Colors.Outline,
						Thickness = Theme.Outline,
					},
					Text(scope, {
						Text = "Бойцы Deluxe",
						Position = UDim2.fromOffset(16, 10),
						Size = UDim2.fromOffset(300, 26),
						Color = Theme.Colors.Paid,
						TextSize = 20,
					}),
					scope:New "Frame" {
						Name = "Cards",
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(16, 40),
						Size = UDim2.fromOffset(556, 300),
						[Children] = {
							scope:New "UIGridLayout" {
								CellPadding = UDim2.fromOffset(8, 8),
								CellSize = UDim2.fromOffset(274, 94),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							cards,
						} :: { Fusion.Child },
					},
					Text(scope, {
						Text = "Платные бойцы не сильнее бесплатных: у всех одинаковый «бюджет» характеристик. "
							.. "Deluxe — это внешний вид: аура, шлейф на рывках, особый фон супера.",
						Font = Theme.Fonts.BodyRegular,
						Position = UDim2.fromOffset(16, 346),
						Size = UDim2.fromOffset(556, 48),
						Color = Theme.Colors.TextDim,
						TextSize = 13,
					}),
				} :: { Fusion.Child },
			},
			scope:New "Frame" {
				Name = "Products",
				BackgroundColor3 = Theme.Colors.Panel,
				BorderSizePixel = 0,
				Position = UDim2.new(0.5, -150, 0, 122),
				Size = UDim2.fromOffset(300, 400),
				Visible = visibleOn("Coins"),
				[Children] = {
					scope:New "UIStroke" {
						Color = Theme.Colors.Outline,
						Thickness = Theme.Outline,
					},
					Text(scope, {
						Text = "Монеты",
						Position = UDim2.fromOffset(16, 10),
						Size = UDim2.fromOffset(268, 26),
						Color = Theme.Colors.Accent,
						TextSize = 20,
					}),
					productButtons,
					Text(scope, {
						Text = "Башня боссов",
						Position = UDim2.fromOffset(16, y + 8),
						Size = UDim2.fromOffset(268, 26),
						Color = Theme.Colors.Accent,
						TextSize = 20,
					}),
					Text(scope, {
						Name = "NextBoss",
						Text = nextBossText,
						Font = Theme.Fonts.BodyRegular,
						Position = UDim2.fromOffset(16, y + 38),
						Size = UDim2.fromOffset(268, 54),
						Color = Theme.Colors.TextDim,
						TextSize = 14,
					}),
					Button(scope, {
						Name = "Product_SkipBoss",
						Text = `Пропустить босса — R$ {skipPrice}`,
						Position = UDim2.fromOffset(16, y + 96),
						Size = UDim2.fromOffset(268, 44),
						TextSize = 16,
						Disabled = scope:Computed(function(use)
							return use(state.bossProgress) >= BossRegistry.count()
						end),
						OnClick = function()
							state.actions.promptProduct("SkipBoss")
						end,
					}),
				} :: { Fusion.Child },
			},
		} :: { Fusion.Child },
	}
end

return Shop
