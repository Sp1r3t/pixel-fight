--!strict
--[[
	Визуальная тема интерфейса: цвета, шрифты, базовое разрешение макета.
	Макеты верстаются в пикселях под ReferenceSize и масштабируются UIScale под экран.
]]

local Theme = table.freeze({
	ReferenceSize = Vector2.new(960, 540),

	Colors = table.freeze({
		Background = Color3.fromHex("#0E0B1A"),
		BackgroundAlt = Color3.fromHex("#1A1233"),
		Panel = Color3.fromHex("#1F1838"),
		PanelLight = Color3.fromHex("#2C2350"),
		Outline = Color3.fromHex("#05030B"),
		Text = Color3.fromHex("#F4F1FF"),
		TextDim = Color3.fromHex("#A69CC8"),
		Accent = Color3.fromHex("#FFC845"),
		Button = Color3.fromHex("#4B3F8F"),
		ButtonPrimary = Color3.fromHex("#E0457B"),
		Disabled = Color3.fromHex("#3A3550"),
		Free = Color3.fromHex("#5BD17A"),
		Paid = Color3.fromHex("#FFB020"),
		StatEmpty = Color3.fromHex("#2A2440"),
	}),

	Fonts = table.freeze({
		-- Пиксельный шрифт — только для латиницы (имена, заголовки).
		Pixel = Enum.Font.Arcade,
		-- Для текста на русском.
		Body = Enum.Font.BuilderSansBold,
		BodyRegular = Enum.Font.BuilderSans,
	}),

	Outline = 3, -- толщина пиксельной обводки
})

return Theme
