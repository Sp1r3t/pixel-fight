--!strict
--[[
	Визуальная тема интерфейса: цвета, шрифты, форма, базовое разрешение макета.
	Макеты верстаются в пикселях под ReferenceSize и масштабируются UIScale под экран.

	Стиль «пиксельно, но не сильно»:
	  • пиксельный шрифт — только для латиницы и цифр (имена, таймер, счёт);
	  • русский текст — крупный округлый BuilderSans, чтобы детям было легко читать;
	  • толстая тёмная обводка, чуть скруглённые углы, «ступенчатая» тень под кнопками;
	  • яркие цвета разделов: розовый — играть, голубой — онлайн, зелёный — тренировка.
]]

local Theme = table.freeze({
	ReferenceSize = Vector2.new(960, 540),

	Colors = table.freeze({
		Background = Color3.fromHex("#110D22"),
		BackgroundAlt = Color3.fromHex("#2A1F58"),
		Panel = Color3.fromHex("#1E1742"),
		PanelLight = Color3.fromHex("#2C2362"),
		PanelEdge = Color3.fromHex("#5A4BB0"), -- светлая кромка сверху панелей
		Outline = Color3.fromHex("#07050F"),
		Text = Color3.fromHex("#F7F4FF"),
		TextDim = Color3.fromHex("#B4AADB"),
		Accent = Color3.fromHex("#FFD23F"),
		Button = Color3.fromHex("#5B4BC4"),
		ButtonPrimary = Color3.fromHex("#FF4F8B"),
		Disabled = Color3.fromHex("#3A3558"),
		Free = Color3.fromHex("#3DDC84"),
		Paid = Color3.fromHex("#FFB020"),
		StatEmpty = Color3.fromHex("#2A2446"),
		Success = Color3.fromHex("#2FC46F"),
		Danger = Color3.fromHex("#FF4D6D"),
		Info = Color3.fromHex("#3AA8F0"),
		Coins = Color3.fromHex("#FFC845"),
	}),

	Fonts = table.freeze({
		-- Пиксельный шрифт — только для латиницы и цифр (имена, заголовки, таймер).
		Pixel = Enum.Font.Arcade,
		-- Заголовки и крупные кнопки на русском.
		Title = Enum.Font.BuilderSansExtraBold,
		-- Обычный текст на русском.
		Body = Enum.Font.BuilderSansBold,
		BodyRegular = Enum.Font.BuilderSans,
	}),

	Outline = 3, -- толщина обводки
	Radius = 8, -- скругление панелей
	ButtonRadius = 10, -- скругление кнопок
	ShadowDepth = 5, -- высота «ступеньки» под кнопкой
})

return Theme
