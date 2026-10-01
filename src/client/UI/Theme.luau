--!strict
--[[
	Визуальная тема интерфейса: цвета, шрифты, форма, базовое разрешение макета.
	Макеты верстаются в пикселях под ReferenceSize и масштабируются UIScale под экран.

	Уголь, состаренная бронза и слоновая кость. Тонкие рамки, строгая типографика.
]]

local Theme = table.freeze({
	ReferenceSize = Vector2.new(960, 540),

	Colors = table.freeze({
		Background = Color3.fromHex("#101820"),
		BackgroundAlt = Color3.fromHex("#283541"),
		Panel = Color3.fromHex("#1B272E"),
		PanelLight = Color3.fromHex("#30434A"),
		PanelEdge = Color3.fromHex("#A47E4F"),
		Outline = Color3.fromHex("#090B09"),
		Text = Color3.fromHex("#E8E0CF"),
		TextDim = Color3.fromHex("#A6A492"),
		Accent = Color3.fromHex("#DBB878"),
		Button = Color3.fromHex("#34454C"),
		ButtonPrimary = Color3.fromHex("#A75A32"),
		Disabled = Color3.fromHex("#292D28"),
		Free = Color3.fromHex("#7D9571"),
		Paid = Color3.fromHex("#94784A"),
		StatEmpty = Color3.fromHex("#272B25"),
		Success = Color3.fromHex("#7D9571"),
		Danger = Color3.fromHex("#AB6251"),
		Info = Color3.fromHex("#627A7D"),
		Coins = Color3.fromHex("#C4A46A"),
		Crystals = Color3.fromHex("#A4AFAD"),
	}),

	Fonts = table.freeze({
		-- Общий шрифт имён, заголовков и таймера (имя свойства сохранено для компонентов).
		Pixel = Enum.Font.GothamBold,
		-- Заголовки и крупные кнопки.
		Title = Enum.Font.GothamBold,
		-- Обычный текст на русском.
		Body = Enum.Font.GothamMedium,
		BodyRegular = Enum.Font.Gotham,
	}),

	Outline = 1,
	Radius = 2,
	ButtonRadius = 2,
	ShadowDepth = 2,
})

return Theme
