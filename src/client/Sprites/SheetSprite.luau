--!strict
--[[
	Отрисовка кадров из спрайт-листа: отдельный ImageLabel на страницу атласа,
	ImageRectOffset/ImageRectSize задают кадр. Страницы загружаются заранее;
	загрузка не блокирует смену кадров и не подменяет пиксельный арт.
	ResampleMode = Pixelated (чёткие пиксели при любом масштабе).

	Кадры слева направо с переносом через sheet.columns, размер frameWidth×frameHeight.
	Строку/число кадров/fps каждой анимации можно задать в Characters[..].sprites.animations,
	иначе берутся значения по умолчанию из Config/Animations.

	Один персонаж может занимать два изображения (sheet.image + sheet.image2, разрез по
	sheet.splitRow) — Roblox портит текстуры со стороной больше ~1024px, поэтому длинные листы
	режутся пополам; переключение между ними — по номеру ряда нужной анимации, прозрачно.

	Зеркалирование (боец смотрит влево): отрицательная ширина ImageRectSize со сдвигом
	ImageRectOffset на правый край кадра.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Types = require(ReplicatedStorage.Shared.Types)
local Animations = require(ReplicatedStorage.Shared.Config.Animations)

export type SheetSprite = {
	root: ImageLabel,
	show: (animation: Types.AnimationName, time: number, progress: number?) -> boolean,
	setFacing: (facing: number) -> (),
	setFlash: (amount: number) -> (),
	setTint: (color: Color3, amount: number) -> (),
	destroy: () -> (),
}

local IDLE: Types.AnimationName = "Idle"

type ResolvedAnimation = { row: number, frames: number, fps: number, loop: boolean, page: number? }

local SheetSprite = {}

-- Параметры анимации с учётом переопределений в листе и запасных анимаций.
local function resolve(sheet: Types.SpriteSheet, animation: Types.AnimationName): ResolvedAnimation
	local current: Types.AnimationName? = animation
	for _ = 1, 4 do
		if current == nil then
			break
		end
		local custom = sheet.animations[current]
		if custom then
			return { row = custom.row, frames = custom.frames, fps = custom.fps, loop = custom.loop, page = custom.page }
		end
		current = Animations.fallbacks[current]
	end
	-- Стандартная раскладка: если строки анимации нет в листе — запасная анимация.
	local name: Types.AnimationName = animation
	for _ = 1, 4 do
		local def = Animations.defaults[name]
		if def and (sheet.rows == nil or def.row < (sheet.rows :: number)) then
			return { row = def.row, frames = def.frames, fps = def.fps, loop = def.loop }
		end
		local fallback = Animations.fallbacks[name]
		if fallback == nil then
			break
		end
		name = fallback :: Types.AnimationName
	end
	local idle = Animations.defaults[IDLE]
	return { row = idle.row, frames = idle.frames, fps = idle.fps, loop = idle.loop }
end

-- Номер кадра (с 0) для момента времени или прогресса удара.
function SheetSprite.frameIndex(anim: ResolvedAnimation, time: number, progress: number?): number
	if anim.frames <= 1 then
		return 0
	end
	if progress ~= nil then
		return math.clamp(math.floor(progress * anim.frames), 0, anim.frames - 1)
	end
	local index = math.floor(time * anim.fps)
	if anim.loop then
		return index % anim.frames
	end
	return math.clamp(index, 0, anim.frames - 1)
end

function SheetSprite.new(parent: Instance, sheet: Types.SpriteSheet): SheetSprite
	local image = Instance.new("ImageLabel")
	image.Name = "Sheet"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = sheet.image
	-- Keep one persistent label per atlas; changing Image can blank the rendered
	-- fighter while Roblox downloads the next page. The root is only a container.
	image.ImageTransparency = 1
	image.ResampleMode = Enum.ResamplerMode.Pixelated
	image.ImageRectSize = Vector2.new(sheet.frameWidth, sheet.frameHeight)
	image.Parent = parent
	local pages: { [string]: ImageLabel } = {}
	local preload: { Instance } = {}
	local sources: { string } = sheet.pages or { sheet.image }
	if sheet.pages == nil and sheet.image2 then
		sources = { sheet.image, sheet.image2 }
	end
	for index, source in sources do
		if pages[source] then
			continue
		end
		local page = Instance.new("ImageLabel")
		page.Name = `Page{index}`
		page.BackgroundTransparency = 1
		page.Size = UDim2.fromScale(1, 1)
		page.Image = source
		page.ResampleMode = Enum.ResamplerMode.Pixelated
		page.ImageRectSize = Vector2.new(sheet.frameWidth, sheet.frameHeight)
		-- Keep pages in the visible tree so the renderer can prepare their textures.
		page.Visible = true
		page.ImageTransparency = 1
		page.Parent = image
		pages[source] = page
		table.insert(preload, page)
	end
	if #preload > 0 then
		task.spawn(function()
			local ok, err = pcall(function()
				ContentProvider:PreloadAsync(preload, function(asset, status)
					if status ~= Enum.AssetFetchStatus.Success then
						warn(`[PixelFight] Sprite atlas failed to load: {asset} ({status.Name})`)
					end
				end)
			end)
			if not ok then
				warn(`[PixelFight] Sprite preload failed: {err}`)
			end
		end)
	end
	local activePage = pages[sheet.image]
	activePage.ImageTransparency = 0

	local facing = 1

	local sprite = {} :: SheetSprite
	sprite.root = image

	function sprite.show(animation: Types.AnimationName, time: number, progress: number?)
		local anim = resolve(sheet, animation)
		local index = SheetSprite.frameIndex(anim, time, progress)
		local idle = animation == "Idle" and sheet.stableIdle == true
		if idle then
			index = 0
		end
		-- The legacy idle moves the entire silhouette. Hold its planted pose and breathe
		-- vertically around the feet until the replacement atlases have been uploaded.
		local height = if idle then 1 + math.sin(time * math.pi) * 0.003 else 1
		image.Size = UDim2.fromScale(1, height)
		image.Position = UDim2.fromScale(0, (1 - height) * 0.96)
		local columns = sheet.columns or anim.frames
		local x = (index % columns) * sheet.frameWidth
		-- Длинные листы режутся на два изображения (Roblox портит текстуры больше ~1024px
		-- по стороне); ряды >= splitRow лежат в image2 под номером (row - splitRow).
		local row = anim.row + math.floor(index / columns)
		local source = sheet.image
		if sheet.pages and anim.page then
			source = sheet.pages[anim.page] or source
		elseif sheet.image2 and sheet.splitRow and row >= sheet.splitRow then
			source = sheet.image2
			row -= sheet.splitRow
		end
		local page = pages[source]
		-- Select the actual visible page before testing readiness. IsLoaded must never
		-- gate visibility or animation: a pending/failed fetch is not an idle pose.
		local y = row * sheet.frameHeight
		if facing >= 0 then
			image.ImageRectOffset = Vector2.new(x, y)
			image.ImageRectSize = Vector2.new(sheet.frameWidth, sheet.frameHeight)
		else
			image.ImageRectOffset = Vector2.new(x + sheet.frameWidth, y)
			image.ImageRectSize = Vector2.new(-sheet.frameWidth, sheet.frameHeight)
		end
		page.ImageRectOffset = image.ImageRectOffset
		page.ImageRectSize = image.ImageRectSize
		if page ~= activePage then
			activePage.ImageTransparency = 1
			activePage = page
		end
		page.ImageTransparency = 0
		image.Image = source
		return page.IsLoaded
	end

	function sprite.setFacing(newFacing: number)
		facing = if newFacing < 0 then -1 else 1
	end

	-- Реакция на удар: ImageColor3 умеет только тонировать, поэтому кадр кратко краснеет.
	function sprite.setFlash(amount: number)
		image.ImageColor3 = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 110, 110), math.clamp(amount, 0, 1))
		for _, page in pages do
			page.ImageColor3 = image.ImageColor3
		end
	end

	function sprite.setTint(color: Color3, amount: number)
		image.ImageColor3 = Color3.new(1, 1, 1):Lerp(color, math.clamp(amount, 0, 1))
		for _, page in pages do
			page.ImageColor3 = image.ImageColor3
		end
	end

	function sprite.destroy()
		image:Destroy()
	end

	sprite.show("Idle", 0, nil)
	return sprite
end

return SheetSprite
