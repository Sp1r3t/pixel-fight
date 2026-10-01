"use strict";
// Сжатый порт src/shared/Config/Characters.luau — только то, что нужно для рисования
// (палитра, тип особого приёма, способ доставки супера, платность для акцентов).

const CHARACTERS = [
	{ id: "rook", order: 1, unlock: "Free", palette: { primary: "#3A6EA5", secondary: "#F2F2F2", accent: "#FFC845" }, specialKind: "Projectile", superDelivery: "Rush" },
	{ id: "mira", order: 2, unlock: "Free", palette: { primary: "#E0457B", secondary: "#2B2B3A", accent: "#FFD166" }, specialKind: "SpinDash", superDelivery: "Rush" },
	{ id: "brakk", order: 3, unlock: "Free", palette: { primary: "#8B5A2B", secondary: "#4A4A4A", accent: "#D9A441" }, specialKind: "CommandGrab", superDelivery: "Grab" },
	{ id: "juno", order: 4, unlock: "Free", palette: { primary: "#2EC4B6", secondary: "#FFFFFF", accent: "#FF9F1C" }, specialKind: "Boomerang", superDelivery: "Barrage" },
	{ id: "sable", order: 5, unlock: "Free", palette: { primary: "#3D2C5E", secondary: "#111111", accent: "#B388FF" }, specialKind: "Teleport", superDelivery: "Rush" },
	{ id: "dax", order: 6, unlock: "Free", palette: { primary: "#C0392B", secondary: "#F5E6CA", accent: "#F1C40F" }, specialKind: "ArmorCharge", superDelivery: "Rush" },
	{ id: "wren", order: 7, unlock: "Free", palette: { primary: "#6AB04C", secondary: "#F0E68C", accent: "#22313F" }, specialKind: "DiveKick", superDelivery: "Launcher" },
	{ id: "sorren", order: 8, unlock: "Free", palette: { primary: "#F39C12", secondary: "#7E3F12", accent: "#FFF3C4" }, specialKind: "Counter", superDelivery: "Counter" },
	{ id: "pike", order: 9, unlock: "Free", palette: { primary: "#5D6D7E", secondary: "#A93226", accent: "#D5DBDB" }, specialKind: "LongThrust", superDelivery: "Beam" },
	{ id: "zip", order: 10, unlock: "Free", palette: { primary: "#F4D03F", secondary: "#1F618D", accent: "#FF5733" }, specialKind: "RushStrike", superDelivery: "Rush" },
	{ id: "ashka", order: 11, unlock: "Paid", palette: { primary: "#FF6B35", secondary: "#7A1E0B", accent: "#FFE66D" }, specialKind: "RisingStrike", superDelivery: "Launcher" },
	{ id: "glacia", order: 12, unlock: "Paid", palette: { primary: "#7FDBFF", secondary: "#E8F8FF", accent: "#2C5F8A" }, specialKind: "GroundWave", superDelivery: "Beam" },
	{ id: "tempest", order: 13, unlock: "Paid", palette: { primary: "#5B5FEF", secondary: "#1B1B2F", accent: "#E6F14A" }, specialKind: "OverheadLeap", superDelivery: "Rush" },
	{ id: "byte", order: 14, unlock: "Paid", palette: { primary: "#00F5A0", secondary: "#141A2E", accent: "#FF3CAC" }, specialKind: "Trap", superDelivery: "Barrage" },
	{ id: "morrow", order: 15, unlock: "Paid", palette: { primary: "#2D2D2D", secondary: "#6C7A89", accent: "#7CFFCB" }, specialKind: "Hook", superDelivery: "Grab" },
	{ id: "astra", order: 16, unlock: "Paid", palette: { primary: "#1A1446", secondary: "#F7F1E3", accent: "#C77DFF" }, specialKind: "ArcProjectile", superDelivery: "Beam" },
];

module.exports = { CHARACTERS };
