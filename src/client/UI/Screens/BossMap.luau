--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Types = require(ReplicatedStorage.Shared.Types)
local BossRegistry = require(ReplicatedStorage.Shared.Characters.BossRegistry)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Layout = require(script.Parent.Parent.CampaignLayout)
local Artwork = require(script.Parent.Parent.CampaignArtwork)
local Button = require(script.Parent.Parent.Components.Button)
local IconGlyph = require(script.Parent.Parent.Components.IconGlyph)
local FighterPortrait = require(script.Parent.Parent.Components.FighterPortrait)
local ScreenHeader = require(script.Parent.Parent.Components.ScreenHeader)
local Panel = require(script.Parent.Parent.Components.Panel)
local MapLandscape = require(script.Parent.Parent.Components.MapLandscape)
local Children, OnEvent, Out, peek = Fusion.Children, Fusion.OnEvent, Fusion.Out, Fusion.peek
type Scope = Fusion.Scope<typeof(Fusion)>
type BossDef = Types.BossDef
export type BossStatus = "Cleared" | "Next" | "Locked"
local GOLD, INK = Color3.fromHex("#DBB878"), Color3.fromHex("#342A20")

local function statusOf(boss: BossDef, progress: number): BossStatus
	return if boss.order <= progress then "Cleared" elseif boss.order == progress + 1 then "Next" else "Locked"
end
local function label(
	scope: Scope,
	name: string,
	text: Fusion.UsedAs<string>,
	x: number,
	y: number,
	w: number,
	h: number,
	size: number,
	color: Color3?
): Instance
	return scope:New "TextLabel" {
		Name = name,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		Text = text,
		TextColor3 = color or Theme.Colors.Text,
		TextSize = size,
		TextScaled = true,
		TextWrapped = true,
		Font = Theme.Fonts.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		[Children] = scope:New "UITextSizeConstraint" { MinTextSize = math.max(10, size - 3), MaxTextSize = size },
	}
end
local function BossCard(scope: Scope, boss: BossDef, state: AppState.AppState, clock: Fusion.Value<number>): Instance
	local status = scope:Computed(function(use)
		return statusOf(boss, use(state.bossProgress))
	end)
	local selected = scope:Computed(function(use)
		return use(state.selectedBossId) == boss.id
	end)
	local hover = scope:Value(false)
	local p = Layout.point(boss.order)
	return scope:New "TextButton" {
		Name = `Boss_{boss.id}`,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(p.X, p.Y),
		Size = UDim2.fromOffset(76, 76),
		ZIndex = 4,
		[OnEvent "Activated"] = function()
			state.selectedBossId:set(boss.id)
		end,
		[OnEvent "MouseEnter"] = function()
			hover:set(true)
		end,
		[OnEvent "MouseLeave"] = function()
			hover:set(false)
		end,
		[Children] = {
			scope:New "UIScale" {
				Scale = scope:Spring(
					scope:Computed(function(use)
						return if use(hover) then 1.08 else 1
					end),
					25,
					0.8
				),
			},
			scope:New "Frame" {
				Name = "Aura",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(106, 106),
				BorderSizePixel = 0,
				BackgroundColor3 = GOLD,
				Visible = selected,
				BackgroundTransparency = scope:Computed(function(use)
					return 0.86 + math.sin(use(clock) * 2) * 0.05
				end),
				[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
			},
			scope:New "Frame" {
				Name = "Medallion",
				Size = UDim2.fromScale(1, 1),
				BorderSizePixel = 0,
				BackgroundColor3 = scope:Computed(function(use)
					return if use(status) == "Locked" then Color3.fromHex("#827D69") else Color3.fromHex("#E4C890")
				end),
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
					scope:New "UIStroke" { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = INK, Thickness = 3 },
					scope:New "UIGradient" {
						Color = ColorSequence.new(Color3.fromHex("#FFF1CC"), Color3.fromHex("#887251")),
						Rotation = 70,
					},
					scope:Computed(function(_use, innerScope: Scope): Instance?
						local def = CharacterRegistry.get(boss.character)
						return if def
							then FighterPortrait(innerScope, {
								Character = def,
								Palette = boss.palette,
								Framing = "Full",
								Facing = -1,
								Silhouette = true,
								Size = UDim2.fromOffset(68, 68),
								Position = UDim2.fromOffset(4, 3),
							})
							else nil
					end),
				} :: { Fusion.Child },
			},
			scope:New "Frame" {
				Name = "SelectedRing",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(90, 90),
				BackgroundTransparency = 1,
				Visible = selected,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
					scope:New "UIStroke" { Color = GOLD, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
				},
			},
			scope:New "TextLabel" {
				Name = "Order",
				BackgroundColor3 = INK,
				BorderSizePixel = 0,
				Font = Theme.Fonts.Body,
				Position = UDim2.fromOffset(24, -12),
				Size = UDim2.fromOffset(28, 19),
				Text = string.format("%02d", boss.order),
				TextSize = 11,
				TextColor3 = GOLD,
				[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
			},
			scope:New "TextLabel" {
				Name = "BossName",
				BackgroundColor3 = INK,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 1, 7),
				Size = UDim2.fromOffset(150, 25),
				Font = Theme.Fonts.Title,
				TextSize = 14,
				TextScaled = true,
				TextColor3 = Theme.Colors.Text,
				Text = scope:Computed(function(use)
					return if use(status) == "Locked" then `БОСС {boss.order}` else string.upper(boss.name)
				end),
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0, 2) },
					scope:New "UITextSizeConstraint" { MinTextSize = 10, MaxTextSize = 14 },
				},
			},
			scope:New "Frame" {
				Name = "Cleared",
				Position = UDim2.fromOffset(58, 0),
				Size = UDim2.fromOffset(22, 22),
				BackgroundColor3 = Theme.Colors.Success,
				BorderSizePixel = 0,
				Visible = scope:Computed(function(use)
					return use(status) == "Cleared"
				end),
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
					IconGlyph(scope, {
						Id = "check",
						Color = Theme.Colors.Text,
						Size = UDim2.fromOffset(16, 16),
						Position = UDim2.fromOffset(3, 3),
					}),
				},
			},
		} :: { Fusion.Child },
	}
end

local function Route(scope: Scope, state: AppState.AppState): Instance
	local pieces: { Instance } = {}
	for order = 1, BossRegistry.count() - 1 do
		local distance, last, start = 0, Layout.curve(order, 0), Layout.curve(order, 0)
		local drawing = true
		for sample = 1, 100 do
			local current = Layout.curve(order, sample / 100)
			distance += (current - last).Magnitude
			last = current
			if distance >= (if drawing then 9 else 7) then
				if drawing then
					local delta, mid = current - start, (current + start) * 0.5
					table.insert(
						pieces,
						scope:New "Frame" {
							Name = `Dash_{order}_{sample}`,
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.fromOffset(mid.X, mid.Y),
							Size = UDim2.fromOffset(delta.Magnitude, 3),
							Rotation = math.deg(math.atan2(delta.Y, delta.X)),
							BorderSizePixel = 0,
							BackgroundColor3 = scope:Computed(function(use)
								return if order <= use(state.bossProgress) then Color3.fromHex("#F9D287") else INK
							end),
							[Children] = {
								scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
								scope:New "UIStroke" {
									Color = Color3.fromHex("#E9D1A0"),
									Thickness = 1,
									Transparency = 0.45,
								},
							},
						}
					)
				end
				drawing = not drawing
				distance, start = 0, current
			end
		end
	end
	return scope:New "Frame" {
		Name = "Route",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		[Children] = pieces,
	}
end

local function DetailsPanel(scope: Scope, boss: BossDef, state: AppState.AppState): Instance
	local status = scope:Computed(function(use)
		return statusOf(boss, use(state.bossProgress))
	end)
	local tier = BossRegistry.tierOf(boss.order)
	local def = CharacterRegistry.get(boss.character)
	local mechanics: { string } = {}
	for _, id in boss.mechanics do
		local mechanic = BossRegistry.MECHANICS[id]
		if mechanic then
			table.insert(mechanics, mechanic.name)
		end
	end
	return Panel(scope, {
		Name = "BossDetails",
		Position = UDim2.fromOffset(24, 398),
		Size = UDim2.fromOffset(912, 124),
		StrokeColor = Theme.Colors.PanelEdge,
		Radius = 5,
		Content = {
			scope:Computed(function(use, innerScope: Scope): Instance?
				return if def
					then FighterPortrait(innerScope, {
						Character = def,
						Palette = boss.palette,
						Framing = "Full",
						Facing = -1,
						Animated = true,
						Silhouette = use(status) == "Locked",
						Size = UDim2.fromOffset(100, 112),
						Position = UDim2.fromOffset(6, 6),
					})
					else nil
			end),
			label(scope, "BossTitle", string.upper(boss.name), 118, 11, 270, 28, 24, GOLD),
			label(scope, "Subtitle", `Босс {boss.order} · {boss.title}`, 118, 42, 270, 20, 13),
			label(
				scope,
				"Status",
				scope:Computed(function(use)
					if use(status) == "Locked" then
						return `Закрыт: сначала победите босса {boss.order - 1}`
					end
					local wins = use(state.bossClears)[boss.id] or 0
					return if wins > 0
						then `Пройден · Побед: {wins}`
						else `Первая победа: {boss.reward} монет`
				end),
				118,
				68,
				288,
				20,
				12,
				Theme.Colors.Accent
			),
			label(
				scope,
				"Fighter",
				scope:Computed(function(use)
					local fighter = CharacterRegistry.get(use(state.selectedCharacterId))
					return `Ваш боец: {if fighter then fighter.displayName else "?"}`
				end),
				118,
				97,
				270,
				17,
				11,
				Theme.Colors.TextDim
			),
			label(scope, "Description", boss.description, 414, 13, 270, 52, 12, Theme.Colors.TextDim),
			label(
				scope,
				"Mechanics",
				`{tier.name} · HP +{math.floor((boss.hpMultiplier - 1) * 100 + 0.5)}%\n{table.concat(mechanics, " · ")}`,
				414,
				70,
				270,
				39,
				12,
				GOLD
			),
			Button(scope, {
				Name = "FightBoss",
				Text = "В БОЙ",
				Icon = "swords",
				Color = Theme.Colors.ButtonPrimary,
				Position = UDim2.fromOffset(706, 15),
				Size = UDim2.fromOffset(188, 48),
				TextSize = 23,
				Disabled = scope:Computed(function(use)
					return use(status) == "Locked"
				end),
				OnClick = function()
					if statusOf(boss, peek(state.bossProgress)) ~= "Locked" then
						state.actions.startBoss(boss.id)
					end
				end,
			}),
			Button(scope, {
				Name = "ChangeFighter",
				Text = "Сменить",
				Position = UDim2.fromOffset(706, 78),
				Size = UDim2.fromOffset(92, 32),
				TextSize = 13,
				OnClick = function()
					AppState.navigate(state, "CharacterSelect")
				end,
			}),
			Button(scope, {
				Name = "SkipBoss",
				Text = "Пропустить",
				Position = UDim2.fromOffset(808, 78),
				Size = UDim2.fromOffset(86, 32),
				TextSize = 12,
				Disabled = scope:Computed(function(use)
					return use(status) ~= "Next"
				end),
				OnClick = function()
					if statusOf(boss, peek(state.bossProgress)) == "Next" then
						state.actions.promptProduct("SkipBoss")
					end
				end,
			}),
		} :: { Fusion.Child },
	})
end

local function BossMap(scope: Scope, state: AppState.AppState): Instance
	local clock = scope:Value(0)
	local elapsed = 0
	table.insert(
		scope,
		RunService.RenderStepped:Connect(function(dt: number)
			elapsed += dt
			if elapsed >= 1 / 20 then
				clock:set(peek(clock) + elapsed)
				elapsed = 0
			end
		end)
	)
	local canvas = scope:Value(Vector2.zero)
	local window = scope:Computed(function(use)
		return math.floor(use(canvas).X / Layout.Width)
	end)
	local chapters: { Fusion.Child } = {}
	for chapter, art in Artwork.chapters do
		local visible = scope:Computed(function(use)
			local first = use(window) + 1
			return chapter >= first - 1 and chapter <= first + 1
		end)
		table.insert(
			chapters,
			scope:Computed(function(use, innerScope: Scope): Instance?
				if not use(visible) then
					return nil
				end
				local title = label(innerScope, `Region_{chapter}`, art.name, 22, 14, 320, 30, 24, INK)
				title.Font = Enum.Font.Garamond
				return innerScope:New "Frame" {
					Name = `ChapterArt_{chapter}`,
					Position = UDim2.fromOffset((chapter - 1) * Layout.Width, 0),
					Size = UDim2.fromOffset(Layout.Width, Layout.Height),
					BackgroundTransparency = 1,
					[Children] = {
						MapLandscape(innerScope, Layout.Width, Layout.Height, false, chapter),
						innerScope:New "Frame" {
							Name = "Captions",
							BackgroundTransparency = 1,
							Size = UDim2.fromScale(1, 1),
							ZIndex = 2,
							[Children] = {
								title,
								label(
									innerScope,
									`Chapter_{chapter}`,
									`ГЛАВА {chapter} / 5`,
									24,
									47,
									190,
									17,
									10,
									INK
								),
							},
						},
					},
				}
			end)
		)
	end
	local width = Layout.Width * #Artwork.chapters
	local cards: { Instance } = {}
	for _, boss in BossRegistry.list() do
		table.insert(cards, BossCard(scope, boss, state, clock))
	end
	local tower = scope:New "ScrollingFrame" {
		Name = "Tower",
		Position = UDim2.fromOffset(24, 76),
		Size = UDim2.fromOffset(Layout.ViewWidth, Layout.Height),
		CanvasSize = UDim2.fromOffset(width, Layout.Height),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = GOLD,
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		[Out "CanvasPosition"] = canvas,
		[Children] = {
			chapters,
			Route(scope, state),
			cards,
		} :: { Fusion.Child },
	} :: ScrollingFrame
	local function scrollTo(x: number)
		tower.CanvasPosition = Vector2.new(math.clamp(x, 0, width - Layout.ViewWidth), 0)
	end
	local navigation: { from: number, target: number, time: number }? = nil
	local dragging, writing = false, false
	local idle: number? = nil
	local function showPage(page: number, animate: boolean?)
		local target = math.clamp(page, 0, #Artwork.chapters - 1) * Layout.Width
		idle = nil
		if animate then
			navigation = { from = tower.CanvasPosition.X, target = target, time = 0 }
		else
			navigation = nil
			writing = true
			scrollTo(target)
			writing = false
		end
	end
	table.insert(
		scope,
		tower:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			if not writing and not navigation then
				idle = 0
			end
		end)
	)
	table.insert(
		scope,
		tower.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				dragging = true
				navigation = nil
			end
		end)
	)
	table.insert(
		scope,
		tower.InputEnded:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				dragging = false
				idle = 0
			end
		end)
	)
	table.insert(
		scope,
		RunService.RenderStepped:Connect(function(dt: number)
			local moving = navigation
			if moving then
				moving.time += dt
				local t = math.min(moving.time / 0.36, 1)
				local eased = t * t * (3 - 2 * t)
				writing = true
				scrollTo(moving.from + (moving.target - moving.from) * eased)
				writing = false
				if t == 1 then
					navigation = nil
				end
			elseif idle ~= nil and not dragging then
				idle += dt
				if idle >= 0.22 then
					showPage(Layout.pageAt(tower.CanvasPosition.X), true)
				end
			end
		end)
	)
	local function turnPage(direction: number)
		local x = if navigation then navigation.target else tower.CanvasPosition.X
		showPage(Layout.pageAt(x) + direction, true)
	end
	scope:Observer(state.selectedBossId):onBind(function()
		local boss = BossRegistry.get(peek(state.selectedBossId))
		if boss then
			showPage(Layout.pageOf(boss.order))
		end
	end)
	return scope:New "Frame" {
		Name = "BossMap",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			ScreenHeader(scope, {
				Title = "ПУТЬ ТЕНИ",
				Coins = state.coins,
				OnBack = function()
					AppState.back(state)
				end,
			}),
			Panel(scope, {
				Name = "MapBorder",
				Position = UDim2.fromOffset(21, 73),
				Size = UDim2.fromOffset(918, 290),
				Color = INK,
				StrokeColor = GOLD,
				Radius = 3,
			}),
			tower,
			label(
				scope,
				"Progress",
				scope:Computed(function(use)
					return `Пройдено: {use(state.bossProgress)} / {BossRegistry.count()}`
				end),
				26,
				370,
				200,
				19,
				13,
				GOLD
			),
			label(
				scope,
				"Legend",
				"Проведите по карте · Выберите противника",
				252,
				371,
				360,
				18,
				11,
				Theme.Colors.TextDim
			),
			Button(scope, {
				Name = "MapPrevious",
				Text = "‹",
				Position = UDim2.fromOffset(828, 367),
				Size = UDim2.fromOffset(48, 27),
				OnClick = function()
					turnPage(-1)
				end,
			}),
			Button(scope, {
				Name = "MapNext",
				Text = "›",
				Position = UDim2.fromOffset(884, 367),
				Size = UDim2.fromOffset(48, 27),
				OnClick = function()
					turnPage(1)
				end,
			}),
			scope:Computed(function(use, innerScope: Scope): Instance?
				local boss = BossRegistry.get(use(state.selectedBossId))
				return if boss then DetailsPanel(innerScope, boss, state) else nil
			end),
		} :: { Fusion.Child },
	}
end
return BossMap
