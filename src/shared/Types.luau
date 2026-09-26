--!strict
--[[
	Общие типы проекта. Только типы — никакой логики и никаких Roblox API,
	поэтому модуль безопасно подключать и на сервере, и на клиенте, и в тестах (Lune).

	Единицы измерения:
	  • время в фреймдате — кадры симуляции (60 кадров = 1 секунда, см. GameConfig.TickRate);
	  • расстояния — студы; ось X — вдоль арены, ось Y — вверх;
	  • цвета в конфигах — HEX-строки ("#RRGGBB"), чтобы конфиги оставались чистыми данными.
]]

export type CharacterId = string

-- Анимации спрайт-листа. Если у персонажа нет какой-то анимации, аниматор
-- использует запасную (например, Dash → Walk, CrouchLight → Light).
export type AnimationName =
	"Idle"
	| "Walk"
	| "Dash"
	| "Jump"
	| "Crouch"
	| "Block"
	| "Light"
	| "Heavy"
	| "CrouchLight"
	| "CrouchHeavy"
	| "AirLight"
	| "AirHeavy"
	| "Special"
	| "Super"
	| "Hit"
	| "Knockdown"
	| "Win"
	| "Lose"

export type SpriteAnimation = {
	row: number, -- строка в спрайт-листе (с 0)
	frames: number, -- количество кадров в строке
	fps: number, -- частота кадров анимации
	loop: boolean,
}

export type SpriteSheet = {
	image: string, -- "rbxassetid://..."
	frameWidth: number, -- размер одного кадра в пикселях
	frameHeight: number,
	rows: number?, -- сколько строк в листе (строки сверх этого берутся из запасных анимаций)
	animations: { [AnimationName]: SpriteAnimation },
}

-- Прямоугольник хитбокса/хартбокса относительно бойца.
-- x — смещение центра ВПЕРЁД по направлению взгляда (зеркалится автоматически),
-- y — высота центра над полом.
export type Box = {
	x: number,
	y: number,
	w: number,
	h: number,
}

export type GuardType = "Mid" | "Low" | "Overhead" | "Unblockable"

-- Фреймдата одного удара/приёма.
export type MoveData = {
	name: string,
	startup: number, -- кадры до первого активного кадра
	active: number, -- кадры, в которые хитбокс активен
	recovery: number, -- кадры восстановления после активных
	damage: number, -- базовый урон (до множителя урона персонажа); у мультихитов — суммарный
	chip: number, -- урон по блоку
	hitstun: number, -- кадры оглушения при попадании
	blockstun: number, -- кадры оглушения при блоке
	hitbox: Box,
	guard: GuardType,
	knockback: number, -- горизонтальная скорость отбрасывания, студ/с
	hits: number?, -- количество попаданий (по умолчанию 1)
	launch: number?, -- вертикальная скорость подброса, студ/с
	knockdown: boolean?, -- сбивает с ног
}

-- Особые приёмы: у каждого персонажа свой уникальный тип.
export type SpecialKind =
	"Projectile"
	| "ArcProjectile"
	| "Boomerang"
	| "GroundWave"
	| "RushStrike"
	| "SpinDash"
	| "ArmorCharge"
	| "RisingStrike"
	| "DiveKick"
	| "OverheadLeap"
	| "Teleport"
	| "Counter"
	| "CommandGrab"
	| "Hook"
	| "LongThrust"
	| "Trap"

-- Способ «доставки» супера. От него зависит допустимый диапазон урона (см. Balance.SuperDamageBands).
export type SuperDelivery = "Rush" | "Launcher" | "Beam" | "Barrage" | "Grab" | "Counter"

-- Параметры, специфичные для типа приёма. Все поля необязательные:
-- каждый тип читает только свои.
export type MoveParams = {
	travelDistance: number?, -- рывки, телепорты, прыжки: насколько далеко перемещается боец
	projectileSpeed: number?, -- снаряды, студ/с
	projectileLifetime: number?, -- секунды
	arcHeight: number?, -- высота дуги (навесные снаряды, прыжковые атаки)
	armorHits: number?, -- сколько ударов «впитывает» броня
	counterWindow: number?, -- кадры окна контратаки
	invincibleFrames: number?, -- кадры неуязвимости на старте
	grabRange: number?, -- дальность захвата
	pullDistance: number?, -- на сколько притягивает противника
	trapLifetime: number?, -- секунды жизни ловушки
}

export type SpecialMove = {
	kind: SpecialKind,
	description: string,
	move: MoveData,
	params: MoveParams,
}

-- Кинематографичная часть супера: запускается, если «триггерный» удар попал.
export type SuperCinematic = {
	style: string, -- id сценария ролика (реализуются на этапе 8)
	duration: number, -- секунды
	hits: number, -- количество ударов в ролике; урон супера делится между ними
}

export type SuperMove = {
	delivery: SuperDelivery,
	description: string,
	move: MoveData, -- «триггерный» удар; урон — полный урон супера
	params: MoveParams,
	cinematic: SuperCinematic,
}

export type StatRatings = {
	health: number,
	damage: number,
	speed: number,
	range: number,
	superGain: number,
}

export type Palette = {
	primary: string,
	secondary: string,
	accent: string,
}

-- Косметика влияет ТОЛЬКО на внешний вид. Боевой код её не читает.
export type CosmeticTier = "Standard" | "Deluxe"

export type Cosmetics = {
	tier: CosmeticTier,
	hitSpark: string, -- id набора частиц при попадании
	superFlash: string, -- цвет вспышки супера (HEX)
	aura: string?, -- id постоянной ауры (только Deluxe)
	trail: string?, -- id шлейфа при рывках (только Deluxe)
	cinematicBackdrop: string?, -- id особого фона ролика супера (только Deluxe)
}

export type UnlockType = "Free" | "Paid"

export type Archetype =
	"AllRounder"
	| "Rushdown"
	| "Grappler"
	| "Zoner"
	| "Assassin"
	| "Bruiser"
	| "Aerial"
	| "Counter"
	| "Spacer"
	| "Speedster"
	| "Trapper"

export type CharacterDef = {
	id: CharacterId,
	order: number, -- порядок в меню выбора
	displayName: string,
	title: string, -- прозвище
	archetype: Archetype,
	style: string, -- описание стиля боя (показывается в меню)
	unlock: UnlockType,
	stats: StatRatings, -- рейтинги 2..8, сумма = Balance.StatBudget
	palette: Palette, -- цвета плейсхолдера, пока нет арта
	cosmetics: Cosmetics,
	special: SpecialMove,
	super: SuperMove,
	sprites: SpriteSheet?, -- nil → процедурный плейсхолдер
}

-- Производные характеристики — то, что реально использует симуляция боя.
export type DerivedStats = {
	maxHealth: number,
	damageMultiplier: number,
	walkSpeed: number, -- студ/с
	rangeMultiplier: number, -- множитель дальности хитбоксов обычных ударов
	superGainMultiplier: number,
}

-- Общий интерфейс сервисов (сервер) и контроллеров (клиент).
-- Init вызывается у всех модулей по порядку, затем Start — у всех в отдельных потоках.
export type Lifecycle = {
	Name: string,
	Init: () -> (),
	Start: () -> (),
}

return nil
