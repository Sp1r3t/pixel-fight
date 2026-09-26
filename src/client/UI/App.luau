--!strict
--[[
	Корневой компонент интерфейса.
	  • ScreenGui на весь экран, фон;
	  • адаптивный масштаб: макеты сверстаны под Theme.ReferenceSize (960×540) и
	    масштабируются UIScale под любой экран (ПК, планшет, телефон);
	  • роутер: показывает экран из state.screen; при смене экрана старый экран
	    уничтожается вместе со своим scope (Fusion 0.3 делает это автоматически в Computed).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local AppState = require(script.Parent.AppState)
local Theme = require(script.Parent.Theme)
local TouchControls = require(script.Parent.Components.TouchControls)

local Screens = script.Parent.Screens
local MainMenu = require(Screens.MainMenu)
local ModeSelect = require(Screens.ModeSelect)
local CharacterSelect = require(Screens.CharacterSelect)
local BossMap = require(Screens.BossMap)
local Shop = require(Screens.Shop)
local ControlsSettings = require(Screens.ControlsSettings)
local Battle = require(Screens.Battle)

local Children, Out, peek = Fusion.Children, Fusion.Out, Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>
type ScreenComponent = (Scope, AppState.AppState) -> Instance

local SCREENS: { [string]: ScreenComponent } = {
	MainMenu = MainMenu,
	ModeSelect = ModeSelect,
	CharacterSelect = CharacterSelect,
	BossMap = BossMap,
	Shop = Shop,
	ControlsSettings = ControlsSettings,
	Battle = Battle,
}

-- Всплывающее уведомление внизу экрана.
local function Notice(scope: Scope, state: AppState.AppState): Instance
	return scope:New "TextLabel" {
		Name = "Notice",
		AnchorPoint = Vector2.new(0.5, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Colors.Panel,
		BorderSizePixel = 0,
		Font = Theme.Fonts.Body,
		Position = UDim2.new(0.5, 0, 1, -60),
		Size = UDim2.fromOffset(0, 40),
		Text = state.notice,
		TextColor3 = Theme.Colors.Text,
		TextSize = 20,
		Visible = scope:Computed(function(use)
			return use(state.notice) ~= ""
		end),
		ZIndex = 50,
		[Children] = {
			scope:New "UIPadding" {
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
			},
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.Colors.Accent,
				Thickness = 2,
			},
		},
	}
end

--[[
	Слой у краёв экрана (вне центрированного макета 960×540): сенсорное управление в бою
	и его редактор на экране «Управление». Кнопки должны быть у краёв на любом соотношении сторон.
]]
local function EdgeLayer(scope: Scope, state: AppState.AppState): Instance
	return scope:New "Frame" {
		Name = "EdgeLayer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		[Children] = scope:Computed(function(use, innerScope: Scope): Instance?
			local screen = use(state.screen)
			if screen == "ControlsSettings" then
				return TouchControls.new(innerScope, {
					Layout = state.controlsDraft,
					UiScale = state.uiScale,
					Editing = true,
					Selected = state.controlsSelected,
				})
			end
			if screen ~= "Battle" then
				return nil
			end
			local battle = use(state.battle)
			local layout = use(state.controlsLayout)
			local localSlot = if battle then battle.localSlot else nil
			if localSlot == nil or not AppState.touchControlsVisible(layout.mode, use(state.platform)) then
				return nil
			end
			local hudFighter = state.hud.fighters[localSlot]
			return TouchControls.new(innerScope, {
				Layout = state.controlsLayout,
				UiScale = state.uiScale,
				Editing = false,
				SuperReady = innerScope:Computed(function(innerUse)
					return innerUse(hudFighter.meter) >= GameConfig.SuperMeter.Max
				end),
				OnPress = function(bit: number)
					state.actions.touchPress(bit)
				end,
				OnHeld = function(mask: number)
					state.actions.touchHeld(mask)
				end,
			})
		end),
	}
end

export type Props = {
	State: AppState.AppState,
	Parent: Instance,
}

local function App(scope: Scope, props: Props): Instance
	local screenSize = scope:Value(Theme.ReferenceSize)
	local uiScale = scope:Computed(function(use)
		local size = use(screenSize)
		local scale = math.min(size.X / Theme.ReferenceSize.X, size.Y / Theme.ReferenceSize.Y)
		return math.clamp(scale, 0.5, 2)
	end)
	scope:Observer(uiScale):onBind(function()
		props.State.uiScale:set(peek(uiScale))
	end)

	return scope:New "ScreenGui" {
		Name = "PixelFightUI",
		DisplayOrder = 10,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = props.Parent,

		[Out "AbsoluteSize"] = screenSize,

		[Children] = {
			scope:New "Frame" {
				Name = "Background",
				BackgroundColor3 = Theme.Colors.Background,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				-- Во время боя виден мир (арена), фон меню скрыт.
				Visible = scope:Computed(function(use)
					return use(props.State.screen) ~= "Battle"
				end),
				ZIndex = 0,
				[Children] = scope:New "UIGradient" {
					Color = ColorSequence.new(Theme.Colors.BackgroundAlt, Theme.Colors.Background),
					Rotation = 90,
				},
			},
			-- Контейнер фиксированного «логического» размера, растянутый UIScale на весь экран.
			scope:New "Frame" {
				Name = "Root",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = scope:Computed(function(use)
					local scale = use(uiScale)
					local size = use(screenSize)
					return UDim2.fromOffset(size.X / scale, size.Y / scale)
				end),
				[Children] = {
					scope:New "UIScale" {
						Scale = uiScale,
					},
					-- Сам макет 960×540 — по центру логического контейнера.
					scope:New "Frame" {
						Name = "Layout",
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundTransparency = 1,
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromOffset(Theme.ReferenceSize.X, Theme.ReferenceSize.Y),
						[Children] = scope:Computed(function(use, innerScope: Scope): Instance
							local screen: ScreenComponent = SCREENS[use(props.State.screen)] or SCREENS.MainMenu
							return screen(innerScope, props.State)
						end),
					},
					EdgeLayer(scope, props.State),
					Notice(scope, props.State),
				},
			},
		},
	}
end

return App
