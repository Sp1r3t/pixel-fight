--!strict
-- Обычные игровые ники для ИИ в публичных и приватных матчах.

local NAMES = {
	"rick823",
	"st1ller",
	"owinerty_po",
	"maxon77",
	"kirill_w",
	"lunarfox12",
	"vladik_pro",
	"neo_kid9",
	"timur404",
	"sasha_play",
	"icebear88",
	"denchik01",
	"m1rage",
	"foxi_27",
	"alex_rush",
	"darkmike5",
	"nikitos_q",
	"ronin311",
	"vortex_kid",
	"artemix90",
	"wildpanda7",
	"serg_o",
	"danik228",
	"pixel_roman",
	"mellow_jay",
	"qwertyson",
	"leon_storm",
	"kira_wave",
	"zxc_nova",
	"mr_frosty",
	"anton_kot",
	"redwolf64",
	"dima_sky",
	"flash_tony",
	"gr1mmy",
	"niko_fast",
	"owlmaster",
	"sunny_riko",
	"ivan_playz",
	"silent_tim",
	"roma_xd",
	"egor_night",
	"mari_kiss",
	"alina_star",
	"katy_pixel",
	"viki_rain",
	"sonya_lime",
	"liza_moon",
	"mia_fire",
	"anya_fly",
	"nastya_cat",
	"polly_wave",
	"dasha_fox",
	"rita_snow",
	"nika_bloom",
	"eva_shadow",
	"turbo_lex",
	"keksik99",
	"minty_zero",
	"bober777",
	"cloud_p",
	"just_orel",
	"ruslan_k",
	"yarik_one",
	"s1mplekid",
	"omega_ray",
	"coolmark13",
	"fedor_mix",
	"ghosty_ua",
	"tiger_maks",
	"noobslayer8",
	"drako_m",
	"stepan_go",
	"mishka_tv",
	"vasya_win",
	"kostya_q",
	"ilya_gg",
	"gamer_pasha",
	"levchik",
	"zakhar_top",
	"robin_lo",
	"samurai_2",
	"orbitron",
	"breeze_x",
	"sokol_15",
	"west_player",
	"northfox",
	"riverkid",
	"little_boss",
	"storm_owl",
	"blacktea7",
	"white_kot",
	"happy_dan",
	"prosto_max",
	"real_oleg",
	"winchester9",
	"skyl1ne",
	"m0onwalk",
	"f1refly",
	"lowkey_tim",
}

assert(#NAMES == 100, `Ожидалось 100 имён ИИ, получено {#NAMES}`)

local BotNames = {}

function BotNames.pick(random: Random, used: { [string]: boolean }?): string
	local occupied = used or {}
	local available: { string } = {}
	for _, name in NAMES do
		if not occupied[string.lower(name)] then
			table.insert(available, name)
		end
	end
	assert(#available > 0, "Все игровые ники заняты")
	return available[random:NextInteger(1, #available)]
end

BotNames.list = table.freeze(NAMES)

return table.freeze(BotNames)
