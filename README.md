# Pixel Fight

2D-файтинг для Roblox с пиксельной графикой: 16 бойцов, 20 боссов в одиночном режиме,
мультиплеер 1 на 1 и 2 на 2. Все персонажи, названия, арт и звуки — оригинальные.

Стек: **Luau (`--!strict`)**, **Rojo 7**, **Fusion 0.3**, Wally, selene, StyLua, luau-lsp, Lune (тесты).

## Статус по этапам

- [x] 1. Структура проекта Rojo + Fusion, модули-заглушки, конфиг персонажей
- [x] 2. Движение, камера и спрайтовая анимация одного персонажа
- [ ] 3. Боевая система на сервере (удары, блок, хитбоксы, урон)
- [ ] 4. Раунды, таймер, HUD на Fusion
- [ ] 5. Мобильное управление
- [ ] 6. ИИ и 20 боссов
- [ ] 7. Мультиплеер 1 на 1, 2 на 2, матчмейкинг
- [ ] 8. Все 16 персонажей и их суперы
- [ ] 9. Монетизация и сохранения
- [ ] 10. Баланс и полировка

## Быстрый старт

```bash
rokit install                      # rojo, wally, selene, stylua, luau-lsp, lune из rokit.toml
rojo serve                         # затем в Studio: плагин Rojo → Connect
# или собрать файл места:
rojo build -o pixel-fight.rbxl
```

Зависимости: **Fusion 0.3.0 уже лежит в `Packages/`** в той же раскладке, что создаёт Wally
(реестр Wally недоступен из облачного окружения, где идёт разработка), поэтому для запуска
ничего ставить не нужно. Обновление пакетов — обычным способом:

```bash
wally install
rojo sourcemap default.project.json -o sourcemap.json
wally-package-types --sourcemap sourcemap.json Packages/   # реэкспорт типов Fusion для --!strict
```

## Управление

| Действие | ПК | Геймпад |
|---|---|---|
| Движение | A / D (← / →) | левый стик, крестовина |
| Прыжок | W, Space (↑) | A, стик вверх |
| Присед | S (↓) | стик вниз |
| Блок | движение назад от противника | то же |
| Рывок / отскок | Shift или двойное нажатие направления | LB / LT |
| «Рука» (лёгкий удар) | J | X |
| «Нога» (тяжёлый удар) | K | Y |
| Особый приём | L | B |
| Супер | I | RB / RT |

Режим **«Тренировка»** в главном меню — бой против неподвижного манекена выбранным бойцом.

## Проверки

```bash
./scripts/check.sh
```

Запускает `stylua --check`, `selene`, `rojo build`, `luau-lsp analyze` (строгая типизация с
определениями Roblox) и тесты `lune run tests/run.luau`.

Тесты запускаются вне Studio: `tests/lib/RobloxRuntime.luau` эмулирует Roblox поверх
`@lune/roblox`, а `tests/lib/Harness.luau` запускает сервер и клиентов в одном процессе, соединяя их
сетевой «петлёй» с настраиваемой задержкой и потерей пакетов. Тесты реально строят интерфейс на Fusion,
нажимают кнопки и клавиши, проводят бой и ловят ошибки вроде опечатки в имени свойства.

Про солверы типов Luau: весь код проходит стабильный солвер без ошибок; общий и серверный код
чист и в новом солвере. В UI-файлах новый солвер пока показывает предупреждения о выводе
дженериков `use`/`peek` — это ограничение типов самой библиотеки Fusion 0.3, на работу игры не влияет.

## Структура

```
default.project.json         дерево Rojo
Packages/                    Fusion 0.3.0 (раскладка Wally)
src/
  shared/  → ReplicatedStorage.Shared
    Types.luau               общие типы (персонажи, фреймдата, хитбоксы, спрайты)
    Config/
      GameConfig.luau        тикрейт 60, раунд 60 с, победы в матче, шкала супера
      Balance.luau           «бюджет силы» и диапазоны урона по типам приёмов
      Characters.luau        16 персонажей — только данные
    Characters/
      CharacterRegistry.luau поиск, производные статы, валидация баланса
    Combat/                  детерминированная симуляция боя 60 Гц, ввод, снапшоты
    Net/                     каналы и Transport (обёртка над Remote*)
  server/  → ServerScriptService.Server
    init.server.luau         загрузчик сервисов (Init → Start)
    Services/                Data, Monetization, Combat, Input, Match, Boss, Matchmaking
    Match/                   объект матча (симуляция + кто управляет бойцами)
    Net/RequestRouter.luau   запросы клиента с лимитом частоты
    AI/                      StateMachine, BossAI
  client/  → StarterPlayerScripts.Client
    init.client.luau         загрузчик контроллеров
    Controllers/             UI, Input, Camera, Effects, Fight
    Fight/                   арена, отрисовка бойцов, интерполяция снапшотов, выбор анимации
    Sprites/                 SpriteAnimator: спрайт-листы (SheetSprite) и плейсхолдер-«кукла» (PuppetSprite)
    UI/                      Fusion: App, AppState, Theme, Components/, Screens/
tests/                       тесты на Lune: симуляция, сеть, античит, UI и интеграция «клиент ↔ сервер»
docs/ARCHITECTURE.md         ключевые архитектурные решения
```

## Персонажи

| # | Персонаж | Архетип | HP/Урон/Скор/Дальн/Супер | Особый приём | Супер | Доступ |
|---|---|---|---|---|---|---|
| 1 | Rook — Street Vanguard | универсал | 5/5/5/5/5 | Pulse Palm (снаряд) | Vanguard Breaker | бесплатно |
| 2 | Mira Voss — Cyclone Kickboxer | скорость | 3/5/8/4/5 | Cyclone Heel (вращение) | Thousand Step Storm | бесплатно |
| 3 | Brakk — Mountain Grappler | борец | 8/7/2/4/4 | Iron Hug (захват) | Tectonic Drop | бесплатно |
| 4 | Juno Hart — Orbit Ace | зонер | 4/4/5/8/4 | Orbit Disc (бумеранг) | Satellite Storm | бесплатно |
| 5 | Sable — Shade Walker | ассасин | 4/6/7/3/5 | Shade Step (телепорт) | Eclipse Execution | бесплатно |
| 6 | Dax Ironside — Knockout Artist | громила | 6/7/5/2/5 | Bulldozer Jab (рывок с бронёй) | Knockout Countdown | бесплатно |
| 7 | Wren — Talon Acrobat | воздушный бой | 4/5/7/4/5 | Talon Dive (пике) | Skyfall Talons | бесплатно |
| 8 | Sorren — Still Water Monk | контратака | 6/5/4/4/6 | Still Water (парирование) | Hundred Lotus | бесплатно |
| 9 | Pike — Longreach Lancer | контроль дистанции | 5/5/3/8/4 | Longreach Lunge (выпад) | Horizon Pierce | бесплатно |
| 10 | Zip — Rocket Rookie | напор | 3/4/8/3/7 | Rocket Rush (рывок) | Afterburner | бесплатно |
| 11 | Ashka — Pyre Dancer | универсал | 4/6/6/4/5 | Phoenix Rise (апперкот) | Solar Coronation | платно |
| 12 | Glacia — Frost Warden | зонер | 6/4/4/6/5 | Frost Line (волна по земле) | Absolute Zero | платно |
| 13 | Tempest — Storm Ronin | громила | 4/7/6/4/4 | Thunderfall (удар сверху) | Storm Sever | платно |
| 14 | Byte — Glitch Operator | ловушки | 5/4/5/5/6 | Glitch Mine (мина) | System Overload | платно |
| 15 | Morrow — Lantern Reaper | контроль дистанции | 6/5/4/6/4 | Soul Hook (крюк) | Last Rites | платно |
| 16 | Astra — Starbound Oracle | зонер | 4/5/5/6/5 | Comet Lob (навесной снаряд) | Supernova | платно |

Сумма рейтингов у всех — 25. Подробности правил баланса — в [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
