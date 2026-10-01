--!strict
--[[
	Вкладки магазина с косметикой (Config/Cosmetics) и премиум-товарами:
	  • Облики — по строке на бойца: «Обычный», «Тень» (монеты), «Легенда» (кристаллы);
	  • Эффекты — искры ударов и финишеры;
	  • Эмоции — смайлики для боя;
	  • Premium — кристаллы, набор новичка, VIP-пропуск.
	Карточка товара показывает цену, после покупки — «Надеть», надетое — «Надето ✓».
	Всё это только внешний вид — сила бойцов не меняется.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Format = require(script.Parent.Parent.Format)
local Button = require(script.Parent.Parent.Components.Button)
local IconGlyph = require(script.Parent.Parent.Components.IconGlyph)
local Panel = require(script.Parent.Parent.Components.Panel)
local FighterPortrait = require(script.Parent.Parent.Components.FighterPortrait)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>
type Item = Cosmetics.Item

local ShopCosmetics = {}

local function slotOf(item: Item): string?
	if item.kind == "Skin" and item.character then
		return `Skin:{item.character}`
	elseif item.kind == "HitEffect" or item.kind == "KoEffect" then
		return item.kind
	end
	return nil
end

local function isEquipped(use: Fusion.Use, state: AppState.AppState, item: Item): boolean
	local equipped = use(state.equipped)
	if item.kind == "Skin" and item.character then
		return equipped.skins[item.character] == item.id
	elseif item.kind == "HitEffect" then
		return equipped.hitEffect == item.id
	elseif item.kind == "KoEffect" then
		return equipped.koEffect == item.id
	end
	return false
end

local function priceText(item: Item): string
	if item.currency == "Coins" then
		return `🪙 {Format.number(item.price)}`
	elseif item.currency == "Crystals" then
		return `💎 {Format.number(item.price)}`
	elseif item.currency == "Vip" then
		return "👑 VIP"
	end
	return "Бесплатно"
end

-- Кнопка под товаром: купить → надеть → надето.
local function ItemButton(scope: Scope, state: AppState.AppState, item: Item, size: UDim2, position: UDim2): Instance
	local owned = scope:Computed(function(use)
		return use(state.items)[item.id] == true
	end)
	local equipped = scope:Computed(function(use)
		return isEquipped(use, state, item)
	end)
	local slot = slotOf(item)
	return Button(scope, {
		Name = `Item_{item.id}`,
		Text = scope:Computed(function(use)
			if not use(owned) then
				return priceText(item)
			elseif slot == nil then
				return "Есть ✓"
			end
			return if use(equipped) then "Надето ✓" else "Надеть"
		end),
		Color = scope:Computed(function(use)
			if not use(owned) then
				return if item.currency == "Crystals" or item.currency == "Vip"
					then Color3.fromHex("#766C80")
					else Color3.fromHex("#94784A")
			end
			return if use(equipped) then Theme.Colors.Success else Theme.Colors.Button
		end),
		Disabled = scope:Computed(function(use)
			return use(owned) and (slot == nil or use(equipped))
		end),
		Size = size,
		Position = position,
		AnchorPoint = Vector2.new(0.5, 1),
		TextSize = 16,
		OnClick = function()
			if not Fusion.peek(owned) then
				if item.currency == "Vip" then
					state.actions.promptVip()
				else
					state.actions.buyItem(item.id)
				end
			elseif slot then
				state.actions.equip(slot, item.id)
			end
		end,
	})
end

-- Карточка эффекта или эмоции: крупная иконка, название, описание, кнопка.
local function ItemCard(scope: Scope, state: AppState.AppState, item: Item, order: number): Instance
	local sample = if item.effect and item.effect.glyph then string.rep(item.effect.glyph, 3) else ""
	return Panel(scope, {
		Name = `Card_{item.id}`,
		LayoutOrder = order,
		Color = Theme.Colors.PanelLight,
		Content = {
			IconGlyph(scope, {
				Name = "Icon",
				Id = item.icon,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 8),
				Size = UDim2.fromOffset(40, 40),
			}),
			scope:New "TextLabel" {
				Name = "Sample",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Title,
				Position = UDim2.fromOffset(0, 50),
				Size = UDim2.new(1, 0, 0, 16),
				Text = sample,
				TextColor3 = if item.effect then Color3.fromHex(item.effect.primary) else Theme.Colors.Text,
				TextSize = 16,
			},
			scope:New "TextLabel" {
				Name = "ItemName",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Title,
				Position = UDim2.fromOffset(6, 66),
				Size = UDim2.new(1, -12, 0, 22),
				Text = item.name,
				TextColor3 = Theme.Colors.Text,
				TextScaled = true,
				[Children] = scope:New "UITextSizeConstraint" { MaxTextSize = 18 },
			},
			ItemButton(scope, state, item, UDim2.new(1, -16, 0, 40), UDim2.new(0.5, 0, 1, -8)),
		},
	})
end

local function Grid(scope: Scope, cell: Vector2, children: { Instance }): { Instance }
	local list: { Instance } = {
		scope:New "UIGridLayout" {
			CellPadding = UDim2.fromOffset(10, 10),
			CellSize = UDim2.fromOffset(cell.X, cell.Y),
			SortOrder = Enum.SortOrder.LayoutOrder,
		},
	}
	for _, child in children do
		table.insert(list, child)
	end
	return list
end

local function Section(scope: Scope, title: string, order: number): Instance
	return scope:New "TextLabel" {
		Name = "Section",
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 28),
		Text = title,
		TextColor3 = Theme.Colors.Accent,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
end

local function Scroller(scope: Scope, name: string, visible: Fusion.UsedAs<boolean>, content: { Instance }): Instance
	return scope:New "ScrollingFrame" {
		Name = name,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		Position = UDim2.fromOffset(24, 122),
		ScrollBarImageColor3 = Theme.Colors.Accent,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.new(1, -48, 0, 404),
		Visible = visible,
		[Children] = {
			scope:New "UIListLayout" {
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			scope:New "UIPadding" {
				PaddingTop = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 10),
			},
			content,
		} :: { Fusion.Child },
	}
end

-- Облики: строка на бойца (обычный + «Тень» + «Легенда»).
function ShopCosmetics.Skins(scope: Scope, state: AppState.AppState, visible: Fusion.UsedAs<boolean>): Instance
	local rows: { Instance } = {}
	for order, def in CharacterRegistry.list() do
		local cards: { Instance } = {}
		local slot = `Skin:{def.id}`
		-- «Обычный» облик — снять надетый.
		table.insert(
			cards,
			Panel(scope, {
				Name = "Default",
				LayoutOrder = 0,
				Color = Theme.Colors.PanelLight,
				Content = {
					FighterPortrait(scope, {
						Character = def,
						Framing = "Bust",
						Size = UDim2.fromOffset(62, 62),
						Position = UDim2.fromOffset(6, 6),
					}),
					scope:New "TextLabel" {
						BackgroundTransparency = 1,
						Font = Theme.Fonts.Title,
						Position = UDim2.fromOffset(74, 8),
						Size = UDim2.new(1, -80, 0, 22),
						Text = "Обычный",
						TextColor3 = Theme.Colors.Text,
						TextSize = 17,
						TextXAlignment = Enum.TextXAlignment.Left,
					},
					Button(scope, {
						Name = `Default_{def.id}`,
						Text = scope:Computed(function(use)
							return if use(state.equipped).skins[def.id] == nil
								then "Надето ✓"
								else "Надеть"
						end),
						Color = scope:Computed(function(use)
							return if use(state.equipped).skins[def.id] == nil
								then Theme.Colors.Success
								else Theme.Colors.Button
						end),
						Disabled = scope:Computed(function(use)
							return use(state.equipped).skins[def.id] == nil
						end),
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.new(0.5, 36, 1, -6),
						Size = UDim2.new(1, -86, 0, 36),
						TextSize = 15,
						OnClick = function()
							state.actions.equip(slot, nil)
						end,
					}),
				},
			})
		)
		for index, skin in Cosmetics.skinsOf(def.id) do
			table.insert(
				cards,
				Panel(scope, {
					Name = `Skin_{skin.id}`,
					LayoutOrder = index,
					Color = Theme.Colors.PanelLight,
					StrokeColor = if skin.legendary then Theme.Colors.Accent else nil,
					Content = {
						FighterPortrait(scope, {
							Character = def,
							Palette = skin.palette,
							Framing = "Bust",
							Size = UDim2.fromOffset(62, 62),
							Position = UDim2.fromOffset(6, 6),
						}),
						scope:New "TextLabel" {
							BackgroundTransparency = 1,
							Font = Theme.Fonts.Title,
							Position = UDim2.fromOffset(74, 8),
							Size = UDim2.new(1, -80, 0, 22),
							Text = skin.name,
							TextColor3 = Theme.Colors.Text,
							TextScaled = true,
							TextXAlignment = Enum.TextXAlignment.Left,
							[Children] = scope:New "UITextSizeConstraint" { MaxTextSize = 17 },
						},
						ItemButton(scope, state, skin, UDim2.new(1, -86, 0, 36), UDim2.new(0.5, 36, 1, -6)),
					},
				})
			)
		end
		table.insert(
			rows,
			scope:New "Frame" {
				Name = `Row_{def.id}`,
				BackgroundTransparency = 1,
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, 84),
				[Children] = {
					scope:New "TextLabel" {
						Name = "Fighter",
						BackgroundTransparency = 1,
						Font = Theme.Fonts.Pixel,
						Size = UDim2.new(0, 120, 1, 0),
						Text = string.upper(def.displayName),
						TextColor3 = Color3.fromHex(def.palette.accent),
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						[Children] = scope:New "UITextSizeConstraint" { MaxTextSize = 20 },
					},
					scope:New "Frame" {
						Name = "Cards",
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(128, 0),
						Size = UDim2.new(1, -128, 1, 0),
						[Children] = Grid(scope, Vector2.new(236, 80), cards),
					},
				},
			}
		)
	end
	return Scroller(scope, "Skins", visible, rows)
end

-- Эффекты ударов и финишеры.
function ShopCosmetics.Effects(scope: Scope, state: AppState.AppState, visible: Fusion.UsedAs<boolean>): Instance
	local function cardsOf(kind: Cosmetics.ItemKind): { Instance }
		local cards: { Instance } = {}
		for index, item in Cosmetics.ofKind(kind) do
			table.insert(cards, ItemCard(scope, state, item, index))
		end
		return cards
	end
	local function block(name: string, order: number, cards: { Instance }): Instance
		local rowsCount = math.ceil(#cards / 6)
		return scope:New "Frame" {
			Name = name,
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, rowsCount * 160),
			[Children] = Grid(scope, Vector2.new(136, 150), cards),
		}
	end
	return Scroller(scope, "Effects", visible, {
		Section(scope, "✨ Эффекты ударов — так выглядят твои попадания", 1),
		block("HitEffects", 2, cardsOf("HitEffect")),
		Section(scope, "🏆 Финишеры — что случится после твоего нокаута", 3),
		block("KoEffects", 4, cardsOf("KoEffect")),
	})
end

-- Эмоции для боя.
function ShopCosmetics.Emotes(scope: Scope, state: AppState.AppState, visible: Fusion.UsedAs<boolean>): Instance
	local cards: { Instance } = {}
	for index, item in Cosmetics.ofKind("Emote") do
		table.insert(cards, ItemCard(scope, state, item, index))
	end
	return Scroller(scope, "Emotes", visible, {
		Section(
			scope,
			"😀 Эмоции: в бою нажми 😀 под таймером и выбери смайлик",
			1
		),
		scope:New "Frame" {
			Name = "Grid",
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 320),
			[Children] = Grid(scope, Vector2.new(136, 150), cards),
		},
	})
end

-- Кристаллы, набор новичка и VIP.
function ShopCosmetics.Premium(scope: Scope, state: AppState.AppState, visible: Fusion.UsedAs<boolean>): Instance
	local buttons: { Instance } = {}
	local y = 44
	for _, product in Monetization.products do
		if product.kind == "Crystals" then
			table.insert(
				buttons,
				Button(scope, {
					Name = `Product_{product.key}`,
					Text = `💎 {product.amount} — R$ {product.priceHint}`,
					Color = Color3.fromHex("#766C80"),
					Position = UDim2.fromOffset(16, y),
					Size = UDim2.new(1, -32, 0, 44),
					TextSize = 17,
					OnClick = function()
						state.actions.promptProduct(product.key)
					end,
				})
			)
			y += 52
		end
	end
	local starterHint = 0
	for _, product in Monetization.products do
		if product.kind == "StarterPack" then
			starterHint = product.priceHint
		end
	end
	local pack = Monetization.starterPack
	return Panel(scope, {
		Name = "Premium",
		Position = UDim2.new(0.5, -60, 0, 122),
		Size = UDim2.fromOffset(440, 400),
		Visible = visible,
		Content = {
			scope:New "TextLabel" {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Title,
				Position = UDim2.fromOffset(16, 10),
				Size = UDim2.new(1, -32, 0, 26),
				Text = "💎 Кристаллы — для обликов и эффектов",
				TextColor3 = Theme.Colors.Accent,
				TextSize = 19,
				TextXAlignment = Enum.TextXAlignment.Left,
			},
			buttons,
			Button(scope, {
				Name = "Product_StarterPack",
				Text = scope:Computed(function(use)
					return if use(state.starterPack)
						then "Набор новичка уже получен ✓"
						else `🎁 Набор новичка — R$ {starterHint}`
				end),
				Subtitle = `{pack.coins} 🪙 + {pack.crystals} 💎 + эмоция 🎉 (один раз)`,
				Color = Theme.Colors.ButtonPrimary,
				Disabled = state.starterPack,
				Position = UDim2.fromOffset(16, y + 8),
				Size = UDim2.new(1, -32, 0, 56),
				TextSize = 18,
				OnClick = function()
					state.actions.promptProduct("StarterPack")
				end,
			}),
			Button(scope, {
				Name = "Vip",
				Text = scope:Computed(function(use)
					return if use(state.vip)
						then "👑 Ты VIP! Спасибо!"
						else `👑 VIP — R$ {Monetization.vipPriceHint}`
				end),
				Subtitle = `+{math.floor((Monetization.vipCoinMultiplier - 1) * 100 + 0.5)}% монет · удар «Радуга» · +{Monetization.vipDailyCrystals} 💎 к подарку дня`,
				Color = Color3.fromHex("#94784A"),
				Disabled = state.vip,
				Position = UDim2.fromOffset(16, y + 76),
				Size = UDim2.new(1, -32, 0, 56),
				TextSize = 18,
				OnClick = function()
					state.actions.promptVip()
				end,
			}),
			scope:New "TextLabel" {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.BodyRegular,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 16, 1, -8),
				Size = UDim2.new(1, -32, 0, 34),
				Text = "Всё это — только внешний вид и удобство: сила бойцов у всех одинаковая.",
				TextColor3 = Theme.Colors.TextDim,
				TextSize = 13,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			},
		} :: { Fusion.Child },
	})
end

return ShopCosmetics
