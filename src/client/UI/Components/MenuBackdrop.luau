--!strict
--[[
	Фон меню: живая пиксельная карта (облака плывут, звёзды мерцают, неон мигает) под тёмной
	вуалью, чтобы интерфейс читался. Карта выбирается случайно из бесплатных при запуске.
	Во время боя фон скрыт и не обновляется (виден настоящий мир арены).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Arenas = require(ReplicatedStorage.Shared.Config.Arenas)
local Theme = require(script.Parent.Parent.Theme)
local ArenaArt = require(script.Parent.Parent.Parent.Fight.ArenaArt)

local Children, peek = Fusion.Children, Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>

export type Props = {
	Visible: Fusion.UsedAs<boolean>,
	ArenaId: string?, -- по умолчанию — случайная бесплатная карта
}

local STEP = 1 / 30

local function pickArena(): Arenas.ArenaTheme
	local free: { Arenas.ArenaTheme } = {}
	for _, arena in Arenas.list do
		if not arena.premium then
			table.insert(free, arena)
		end
	end
	return free[math.random(1, #free)]
end

local function MenuBackdrop(scope: Scope, props: Props): Instance
	local theme = (if props.ArenaId then Arenas.byId[props.ArenaId] else nil) or pickArena()

	local holder = scope:New "Frame" {
		Name = "Scene",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}
	local _, art = ArenaArt.scene(holder, theme)

	local root = scope:New "Frame" {
		Name = "Background",
		BackgroundColor3 = Theme.Colors.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
		Visible = props.Visible,
		ZIndex = 0,
		[Children] = {
			holder,
			-- Вуаль: сверху светлее (видно небо), к низу темнее (там кнопки и текст).
			scope:New "Frame" {
				Name = "Veil",
				BackgroundColor3 = Theme.Colors.Background,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 30,
				[Children] = scope:New "UIGradient" {
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.55),
						NumberSequenceKeypoint.new(0.6, 0.35),
						NumberSequenceKeypoint.new(1, 0.15),
					}),
				},
			},
		},
	}

	-- Анимации сцены (~30 кадров/с), только пока фон виден.
	local pending = 0
	table.insert(
		scope,
		RunService.RenderStepped:Connect(function(dt: number)
			if not peek(props.Visible) then
				return
			end
			pending += dt
			if pending >= STEP then
				art.update(math.min(pending, 0.1))
				pending = 0
			end
		end)
	)

	return root
end

return MenuBackdrop
