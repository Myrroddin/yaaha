-- Maps equipment-enchant spell IDs to auctionable scrolls and compatible vellums.

local LibStub = LibStub

local addon = LibStub("AceAddon-3.0"):GetAddon("YAAHA")
local module = addon:NewModule("EnchantingScrollData")
local isMists = addon.IsMists

local ARMOR = 4
local WEAPON = 2

-- [enchantSpellID] = {scrollItemID, targetItemClass, requiredItemLevel}
-- Wrath's vellum restrictions are cumulative: a higher tier can also hold every
-- enchant accepted by the lower tiers.
local enchants = {
	-- Enchants introduced in Classic Era.
	[7418] = {38679, 4, 0}, -- Enchant Bracer - Minor Health
	[7420] = {38766, 4, 0}, -- Enchant Chest - Minor Health
	[7426] = {38767, 4, 0}, -- Enchant Chest - Minor Absorption
	[7428] = {38768, 4, 0}, -- Enchant Bracer - Minor Dodge
	[7443] = {38769, 4, 0}, -- Enchant Chest - Minor Mana
	[7457] = {38771, 4, 0}, -- Enchant Bracer - Minor Stamina
	[7745] = {38772, 2, 0}, -- Enchant 2H Weapon - Minor Impact
	[7748] = {38773, 4, 0}, -- Enchant Chest - Lesser Health
	[7766] = {38774, 4, 0}, -- Enchant Bracer - Minor Versatility
	[7771] = {38775, 4, 0}, -- Enchant Cloak - Minor Protection
	[7776] = {38776, 4, 0}, -- Enchant Chest - Lesser Mana
	[7779] = {38777, 4, 0}, -- Enchant Bracer - Minor Agility
	[7782] = {38778, 4, 0}, -- Enchant Bracer - Minor Strength
	[7786] = {38779, 2, 0}, -- Enchant Weapon - Minor Beastslayer
	[7788] = {38780, 2, 0}, -- Enchant Weapon - Minor Striking
	[7793] = {38781, 2, 0}, -- Enchant 2H Weapon - Lesser Intellect
	[7857] = {38782, 4, 0}, -- Enchant Chest - Health
	[7859] = {38783, 4, 0}, -- Enchant Bracer - Lesser Versatility
	[7863] = {38785, 4, 0}, -- Enchant Boots - Minor Stamina
	[7867] = {38786, 4, 0}, -- Enchant Boots - Minor Agility
	[13378] = {38787, 4, 0}, -- Enchant Shield - Minor Stamina
	[13380] = {38788, 2, 0}, -- Enchant 2H Weapon - Lesser Versatility
	[13419] = {38789, 4, 0}, -- Enchant Cloak - Minor Agility
	[13421] = {38790, 4, 0}, -- Enchant Cloak - Lesser Protection
	[13464] = {38791, 4, 0}, -- Enchant Shield - Lesser Protection
	[13485] = {38792, 4, 0}, -- Enchant Shield - Lesser Versatility
	[13501] = {38793, 4, 0}, -- Enchant Bracer - Lesser Stamina
	[13503] = {38794, 2, 0}, -- Enchant Weapon - Lesser Striking
	[13529] = {38796, 2, 0}, -- Enchant 2H Weapon - Lesser Impact
	[13536] = {38797, 4, 0}, -- Enchant Bracer - Lesser Strength
	[13538] = {38798, 4, 0}, -- Enchant Chest - Lesser Absorption
	[13607] = {38799, 4, 0}, -- Enchant Chest - Mana
	[13612] = {38800, 4, 0}, -- Enchant Gloves - Mining
	[13617] = {38801, 4, 0}, -- Enchant Gloves - Herbalism
	[13620] = {38802, 4, 0}, -- Enchant Gloves - Fishing
	[13622] = {38803, 4, 0}, -- Enchant Bracer - Lesser Intellect
	[13626] = {38804, 4, 0}, -- Enchant Chest - Minor Stats
	[13631] = {38805, 4, 0}, -- Enchant Shield - Lesser Stamina
	[13635] = {38806, 4, 0}, -- Enchant Cloak - Defense
	[13637] = {38807, 4, 0}, -- Enchant Boots - Lesser Agility
	[13640] = {38808, 4, 0}, -- Enchant Chest - Greater Health
	[13642] = {38809, 4, 0}, -- Enchant Bracer - Versatility
	[13644] = {38810, 4, 0}, -- Enchant Boots - Lesser Stamina
	[13646] = {38811, 4, 0}, -- Enchant Bracer - Lesser Dodge
	[13648] = {38812, 4, 0}, -- Enchant Bracer - Stamina
	[13653] = {38813, 2, 0}, -- Enchant Weapon - Lesser Beastslayer
	[13655] = {38814, 2, 0}, -- Enchant Weapon - Lesser Elemental Slayer
	[13659] = {38816, 4, 0}, -- Enchant Shield - Versatility
	[13661] = {38817, 4, 0}, -- Enchant Bracer - Strength
	[13663] = {38818, 4, 0}, -- Enchant Chest - Greater Mana
	[13687] = {38819, 4, 0}, -- Enchant Boots - Lesser Versatility
	[13689] = {38820, 4, 0}, -- Enchant Shield - Lesser Parry
	[13693] = {38821, 2, 0}, -- Enchant Weapon - Striking
	[13695] = {38822, 2, 0}, -- Enchant 2H Weapon - Impact
	[13698] = {38823, 4, 0}, -- Enchant Gloves - Skinning
	[13700] = {38824, 4, 0}, -- Enchant Chest - Lesser Stats
	[13746] = {38825, 4, 0}, -- Enchant Cloak - Greater Defense
	[13815] = {38827, 4, 0}, -- Enchant Gloves - Agility
	[13817] = {38828, 4, 0}, -- Enchant Shield - Stamina
	[13822] = {38829, 4, 0}, -- Enchant Bracer - Intellect
	[13836] = {38830, 4, 0}, -- Enchant Boots - Stamina
	[13841] = {38831, 4, 0}, -- Enchant Gloves - Advanced Mining
	[13846] = {38832, 4, 0}, -- Enchant Bracer - Greater Versatility
	[13858] = {38833, 4, 0}, -- Enchant Chest - Superior Health
	[13868] = {38834, 4, 0}, -- Enchant Gloves - Advanced Herbalism
	[13882] = {38835, 4, 0}, -- Enchant Cloak - Lesser Agility
	[13887] = {38836, 4, 0}, -- Enchant Gloves - Strength
	[13890] = {38837, 4, 0}, -- Enchant Boots - Minor Speed
	[13898] = {38838, 2, 0}, -- Enchant Weapon - Fiery Weapon
	[13905] = {38839, 4, 0}, -- Enchant Shield - Greater Versatility
	[13915] = {38840, 2, 0}, -- Enchant Weapon - Demonslaying
	[13917] = {38841, 4, 0}, -- Enchant Chest - Superior Mana
	[13931] = {38842, 4, 0}, -- Enchant Bracer - Dodge
	[13935] = {38844, 4, 0}, -- Enchant Boots - Agility
	[13937] = {38845, 2, 0}, -- Enchant 2H Weapon - Greater Impact
	[13939] = {38846, 4, 0}, -- Enchant Bracer - Greater Strength
	[13941] = {38847, 4, 0}, -- Enchant Chest - Stats
	[13943] = {38848, 2, 0}, -- Enchant Weapon - Greater Striking
	[13945] = {38849, 4, 0}, -- Enchant Bracer - Greater Stamina
	[13947] = {38850, 4, 0}, -- Enchant Gloves - Riding Skill
	[13948] = {38851, 4, 0}, -- Enchant Gloves - Minor Haste
	[20008] = {38852, 4, 0}, -- Enchant Bracer - Greater Intellect
	[20009] = {38853, 4, 0}, -- Enchant Bracer - Superior Versatility
	[20010] = {38854, 4, 0}, -- Enchant Bracer - Superior Strength
	[20011] = {38855, 4, 0}, -- Enchant Bracer - Superior Stamina
	[20012] = {38856, 4, 0}, -- Enchant Gloves - Greater Agility
	[20013] = {38857, 4, 0}, -- Enchant Gloves - Greater Strength
	[20015] = {38859, 4, 0}, -- Enchant Cloak - Superior Defense
	[20016] = {38860, 4, 0}, -- Enchant Shield - Vitality
	[20017] = {38861, 4, 0}, -- Enchant Shield - Greater Stamina
	[20020] = {38862, 4, 0}, -- Enchant Boots - Greater Stamina
	[20023] = {38863, 4, 0}, -- Enchant Boots - Greater Agility
	[20024] = {38864, 4, 0}, -- Enchant Boots - Versatility
	[20025] = {38865, 4, 0}, -- Enchant Chest - Greater Stats
	[20026] = {38866, 4, 0}, -- Enchant Chest - Major Health
	[20028] = {38867, 4, 0}, -- Enchant Chest - Major Mana
	[20029] = {38868, 2, 0}, -- Enchant Weapon - Icy Chill
	[20030] = {38869, 2, 0}, -- Enchant 2H Weapon - Superior Impact
	[20031] = {38870, 2, 0}, -- Enchant Weapon - Superior Striking
	[20032] = {38871, 2, 0}, -- Enchant Weapon - Lifestealing
	[20033] = {38872, 2, 0}, -- Enchant Weapon - Unholy Weapon
	[20034] = {38873, 2, 0}, -- Enchant Weapon - Crusader
	[20035] = {38874, 2, 0}, -- Enchant 2H Weapon - Major Versatility
	[20036] = {38875, 2, 0}, -- Enchant 2H Weapon - Major Intellect
	[21931] = {38876, 2, 0}, -- Enchant Weapon - Winter's Might
	[22749] = {38877, 2, 0}, -- Enchant Weapon - Spellpower
	[22750] = {38878, 2, 0}, -- Enchant Weapon - Healing Power
	[23799] = {38879, 2, 0}, -- Enchant Weapon - Strength
	[23800] = {38880, 2, 0}, -- Enchant Weapon - Agility
	[23801] = {38881, 4, 0}, -- Enchant Bracer - Argent Versatility
	[23802] = {38882, 4, 0}, -- Enchant Bracer - Healing Power
	[23803] = {38883, 2, 0}, -- Enchant Weapon - Mighty Versatility
	[23804] = {38884, 2, 0}, -- Enchant Weapon - Mighty Intellect
	[25072] = {38885, 4, 0}, -- Enchant Gloves - Threat
	[25073] = {38886, 4, 0}, -- Enchant Gloves - Shadow Power
	[25074] = {38887, 4, 0}, -- Enchant Gloves - Frost Power
	[25078] = {38888, 4, 0}, -- Enchant Gloves - Fire Power
	[25079] = {38889, 4, 0}, -- Enchant Gloves - Healing Power
	[25080] = {38890, 4, 0}, -- Enchant Gloves - Superior Agility
	[25083] = {38893, 4, 0}, -- Enchant Cloak - Stealth
	[25084] = {38894, 4, 0}, -- Enchant Cloak - Subtlety
	[25086] = {38895, 4, 35}, -- Enchant Cloak - Dodge
	[27837] = {38896, 2, 0}, -- Enchant 2H Weapon - Agility

	-- Enchants introduced in The Burning Crusade.
	[27899] = {38897, 4, 35}, -- Enchant Bracer - Brawn
	[27905] = {38898, 4, 35}, -- Enchant Bracer - Stats
	[27906] = {38899, 4, 35}, -- Enchant Bracer - Greater Dodge
	[27911] = {38900, 4, 35}, -- Enchant Bracer - Superior Healing
	[27913] = {38901, 4, 35}, -- Enchant Bracer - Versatility Prime
	[27914] = {38902, 4, 35}, -- Enchant Bracer - Fortitude
	[27917] = {38903, 4, 35}, -- Enchant Bracer - Spellpower
	[27944] = {38904, 4, 35}, -- Enchant Shield - Lesser Dodge
	[27945] = {38905, 4, 35}, -- Enchant Shield - Intellect
	[27946] = {38906, 4, 35}, -- Enchant Shield - Parry
	[27948] = {38908, 4, 35}, -- Enchant Boots - Vitality
	[27950] = {38909, 4, 35}, -- Enchant Boots - Fortitude
	[27951] = {37603, 4, 35}, -- Enchant Boots - Dexterity
	[27954] = {38910, 4, 35}, -- Enchant Boots - Surefooted
	[27957] = {38911, 4, 35}, -- Enchant Chest - Exceptional Health
	[27958] = {38912, 4, 60}, -- Enchant Chest - Exceptional Mana
	[27960] = {38913, 4, 35}, -- Enchant Chest - Exceptional Stats
	[27961] = {38914, 4, 35}, -- Enchant Cloak - Major Armor
	[27967] = {38917, 2, 35}, -- Enchant Weapon - Major Striking
	[27968] = {38918, 2, 35}, -- Enchant Weapon - Major Intellect
	[27971] = {38919, 2, 35}, -- Enchant 2H Weapon - Savagery
	[27972] = {38920, 2, 35}, -- Enchant Weapon - Potency
	[27975] = {38921, 2, 35}, -- Enchant Weapon - Major Spellpower
	[27977] = {38922, 2, 35}, -- Enchant 2H Weapon - Major Agility
	[27981] = {38923, 2, 35}, -- Enchant Weapon - Sunfire
	[27982] = {38924, 2, 35}, -- Enchant Weapon - Soulfrost
	[27984] = {38925, 2, 35}, -- Enchant Weapon - Mongoose
	[28003] = {38926, 2, 35}, -- Enchant Weapon - Spellsurge
	[28004] = {38927, 2, 35}, -- Enchant Weapon - Battlemaster
	[33990] = {38928, 4, 35}, -- Enchant Chest - Major Versatility
	[33991] = {38929, 4, 35}, -- Enchant Chest - Versatility Prime
	[33992] = {38930, 4, 35}, -- Enchant Chest - Major Armor
	[33993] = {38931, 4, 35}, -- Enchant Gloves - Blasting
	[33994] = {38932, 4, 35}, -- Enchant Gloves - Precise Strikes
	[33995] = {38933, 4, 35}, -- Enchant Gloves - Major Strength
	[33996] = {38934, 4, 35}, -- Enchant Gloves - Assault
	[33997] = {38935, 4, 35}, -- Enchant Gloves - Major Spellpower
	[33999] = {38936, 4, 35}, -- Enchant Gloves - Major Healing
	[34001] = {38937, 4, 35}, -- Enchant Bracer - Major Intellect
	[34002] = {38938, 4, 35}, -- Enchant Bracer - Lesser Assault
	[34003] = {38939, 4, 35}, -- Enchant Cloak - Empowerment
	[34004] = {38940, 4, 35}, -- Enchant Cloak - Greater Agility
	[34007] = {38943, 4, 35}, -- Enchant Boots - Cat's Swiftness
	[34008] = {38944, 4, 35}, -- Enchant Boots - Boar's Speed
	[34009] = {38945, 4, 35}, -- Enchant Shield - Major Stamina
	[34010] = {38946, 2, 35}, -- Enchant Weapon - Major Healing
	[42620] = {38947, 2, 35}, -- Enchant Weapon - Greater Agility
	[42974] = {38948, 2, 60}, -- Enchant Weapon - Executioner

	-- Enchants introduced in Wrath of the Lich King.
	[44383] = {38949, 4, 35}, -- Enchant Shield - Armor
	[44484] = {38951, 4, 60}, -- Enchant Gloves - Haste
	[44488] = {38953, 4, 60}, -- Enchant Gloves - Precision
	[44489] = {38954, 4, 60}, -- Enchant Shield - Dodge
	[44492] = {38955, 4, 60}, -- Enchant Chest - Mighty Health
	[44500] = {38959, 4, 60}, -- Enchant Cloak - Superior Agility
	[44506] = {38960, 4, 60}, -- Enchant Gloves - Gatherer
	[44508] = {38961, 4, 60}, -- Enchant Boots - Greater Versatility
	[44509] = {38962, 4, 60}, -- Enchant Chest - Greater Versatility
	[44510] = {38963, 2, 60}, -- Enchant Weapon - Exceptional Versatility
	[44513] = {38964, 4, 60}, -- Enchant Gloves - Greater Assault
	[44524] = {38965, 2, 60}, -- Enchant Weapon - Icebreaker
	[44528] = {38966, 4, 60}, -- Enchant Boots - Greater Fortitude
	[44529] = {38967, 4, 60}, -- Enchant Gloves - Major Agility
	[44555] = {38968, 4, 60}, -- Enchant Bracer - Exceptional Intellect
	[60616] = {38971, 4, 60}, -- Enchant Bracer - Assault
	[44576] = {38972, 2, 60}, -- Enchant Weapon - Lifeward
	[44582] = {38973, 4, 60}, -- Enchant Cloak - Minor Power
	[44584] = {38974, 4, 60}, -- Enchant Boots - Greater Vitality
	[44588] = {38975, 4, 60}, -- Enchant Chest - Exceptional Armor
	[44589] = {38976, 4, 60}, -- Enchant Boots - Superior Agility
	[44591] = {38978, 4, 60}, -- Enchant Cloak - Superior Dodge
	[44592] = {38979, 4, 60}, -- Enchant Gloves - Exceptional Spellpower
	[44593] = {38980, 4, 60}, -- Enchant Bracer - Major Versatility
	[44595] = {38981, 2, 60}, -- Enchant 2H Weapon - Scourgebane
	[44598] = {38984, 4, 60}, -- Enchant Bracer - Haste
	[44612] = {38985, 4, 60}, -- Enchant Gloves - Greater Blasting
	[60623] = {38986, 4, 60}, -- Enchant Boots - Icewalker
	[44616] = {38987, 4, 60}, -- Enchant Bracer - Greater Stats
	[44621] = {38988, 2, 60}, -- Enchant Weapon - Giant Slayer
	[44623] = {38989, 4, 60}, -- Enchant Chest - Super Stats
	[44625] = {38990, 4, 60}, -- Enchant Gloves - Armsman
	[44629] = {38991, 2, 60}, -- Enchant Weapon - Exceptional Spellpower
	[44630] = {38992, 2, 60}, -- Enchant 2H Weapon - Greater Savagery
	[44631] = {38993, 4, 60}, -- Enchant Cloak - Shadow Armor
	[44633] = {38995, 2, 60}, -- Enchant Weapon - Exceptional Agility
	[44635] = {38997, 4, 60}, -- Enchant Bracer - Greater Spellpower
	[46578] = {38998, 2, 60}, -- Enchant Weapon - Deathfrost
	[46594] = {38999, 4, 35}, -- Enchant Chest - Dodge
	[47051] = {39000, 4, 35}, -- Enchant Cloak - Greater Dodge
	[47672] = {39001, 4, 60}, -- Enchant Cloak - Mighty Stamina
	[47766] = {39002, 4, 60}, -- Enchant Chest - Greater Dodge
	[47898] = {39003, 4, 60}, -- Enchant Cloak - Greater Speed
	[47899] = {39004, 4, 60}, -- Enchant Cloak - Wisdom
	[47900] = {39005, 4, 60}, -- Enchant Chest - Super Health
	[47901] = {39006, 4, 60}, -- Enchant Boots - Tuskarr's Vitality
	[59625] = {43987, 2, 60}, -- Enchant Weapon - Black Magic
	[60606] = {44449, 4, 60}, -- Enchant Boots - Assault
	[60621] = {44453, 2, 60}, -- Enchant Weapon - Greater Potency
	[60653] = {44455, 4, 60}, -- Shield Enchant - Greater Intellect
	[60609] = {44456, 4, 60}, -- Enchant Cloak - Speed
	[60663] = {44457, 4, 60}, -- Enchant Cloak - Major Agility
	[60668] = {44458, 4, 60}, -- Enchant Gloves - Crusher
	[60691] = {44463, 2, 60}, -- Enchant 2H Weapon - Massacre
	[60692] = {44465, 4, 60}, -- Enchant Chest - Powerful Stats
	[60707] = {44466, 2, 60}, -- Enchant Weapon - Superior Potency
	[60714] = {44467, 2, 60}, -- Enchant Weapon - Mighty Spellpower
	[60763] = {44469, 4, 60}, -- Enchant Boots - Greater Assault
	[60767] = {44470, 4, 60}, -- Enchant Bracer - Superior Spellpower
	[59621] = {44493, 2, 60}, -- Enchant Weapon - Berserking
	[59619] = {44497, 2, 60}, -- Enchant Weapon - Accuracy
	[44575] = {44815, 4, 60}, -- Enchant Bracer - Greater Assault
	[62257] = {44946, 2, 60}, -- Enchant Weapon - Titanguard
	[62256] = {44947, 4, 60}, -- Enchant Bracer - Major Stamina
	[62948] = {45056, 2, 60}, -- Enchant Staff - Greater Spellpower
	[62959] = {45060, 2, 60}, -- Enchant Staff - Spellpower
	[63746] = {45628, 4, 60}, -- Enchant Boots - Lesser Accuracy
	[64441] = {46026, 2, 60}, -- Enchant Weapon - Blade Ward
	[64579] = {46098, 2, 60}, -- Enchant Weapon - Blood Draining
}

-- Mists Classic folds Cataclysm and Mists into one client. These entries extend
-- the Wrath baseline only there; every equipment enchant uses one universal
-- Enchanting Vellum, so target class and enchantment level are unnecessary.
if isMists then
	-- Enchants introduced in Cataclysm.
	enchants[71692] = {50816} -- Enchant Gloves - Angler
	enchants[74132] = {52687} -- Enchant Gloves - Mastery
	enchants[74189] = {52743} -- Enchant Boots - Earthen Vitality
	enchants[74191] = {52744} -- Enchant Chest - Mighty Stats
	enchants[74192] = {52745} -- Enchant Cloak - Lesser Power
	enchants[74193] = {52746} -- Enchant Bracer - Speed
	enchants[74195] = {52747} -- Enchant Weapon - Mending
	enchants[74197] = {52748} -- Enchant Weapon - Avalanche
	enchants[74198] = {52749} -- Enchant Gloves - Haste
	enchants[74199] = {52750} -- Enchant Boots - Haste
	enchants[74200] = {52751} -- Enchant Chest - Stamina
	enchants[74201] = {52752} -- Enchant Bracer - Critical Strike
	enchants[74202] = {52753} -- Enchant Cloak - Intellect
	enchants[74207] = {52754} -- Enchant Shield - Protection
	enchants[74211] = {52755} -- Enchant Weapon - Elemental Slayer
	enchants[74212] = {52756} -- Enchant Gloves - Exceptional Strength
	enchants[74213] = {52757} -- Enchant Boots - Major Agility
	enchants[74214] = {52758} -- Enchant Chest - Mighty Armor
	enchants[74220] = {52759} -- Enchant Gloves - Greater Haste
	enchants[74223] = {52760} -- Enchant Weapon - Hurricane
	enchants[74225] = {52761} -- Enchant Weapon - Heartsong
	enchants[74226] = {52762} -- Enchant Shield - Mastery
	enchants[74229] = {52763} -- Enchant Bracer - Superior Dodge
	enchants[74230] = {52764} -- Enchant Cloak - Critical Strike
	enchants[74231] = {52765} -- Enchant Chest - Exceptional Versatility
	enchants[74232] = {52766} -- Enchant Bracer - Precision
	enchants[74234] = {52767} -- Enchant Cloak - Protection
	enchants[74235] = {52768} -- Enchant Off-Hand - Superior Intellect
	enchants[74236] = {52769} -- Enchant Boots - Precision
	enchants[74237] = {52770} -- Enchant Bracer - Exceptional Versatility
	enchants[74238] = {52771} -- Enchant Boots - Mastery
	enchants[74239] = {52772} -- Enchant Bracer - Greater Haste
	enchants[74240] = {52773} -- Enchant Cloak - Greater Intellect
	enchants[74242] = {52774} -- Enchant Weapon - Power Torrent
	enchants[74244] = {52775} -- Enchant Weapon - Windwalk
	enchants[74246] = {52776} -- Enchant Weapon - Landslide
	enchants[74247] = {52777} -- Enchant Cloak - Greater Critical Strike
	enchants[74248] = {52778} -- Enchant Bracer - Greater Critical Strike
	enchants[74250] = {52779} -- Enchant Chest - Peerless Stats
	enchants[74251] = {52780} -- Enchant Chest - Greater Stamina
	enchants[74252] = {52781} -- Enchant Boots - Assassin's Step
	enchants[74253] = {52782} -- Enchant Boots - Lavawalker
	enchants[74254] = {52783} -- Enchant Gloves - Mighty Strength
	enchants[74255] = {52784} -- Enchant Gloves - Greater Mastery
	enchants[74256] = {52785} -- Enchant Bracer - Greater Speed
	enchants[95471] = {68134} -- Enchant 2H Weapon - Mighty Agility
	enchants[96261] = {68785} -- Enchant Bracer - Major Strength
	enchants[96262] = {68786} -- Enchant Bracer - Mighty Intellect
	enchants[96264] = {68784} -- Enchant Bracer - Agility

	-- Enchants introduced in Mists of Pandaria.
	enchants[104338] = {74700} -- Enchant Bracer - Mastery
	enchants[104385] = {74701} -- Enchant Bracer - Major Dodge
	enchants[104389] = {74703} -- Enchant Bracer - Super Intellect
	enchants[104390] = {74704} -- Enchant Bracer - Exceptional Strength
	enchants[104391] = {74705} -- Enchant Bracer - Greater Agility
	enchants[104392] = {74706} -- Enchant Chest - Super Armor
	enchants[104393] = {74707} -- Enchant Chest - Mighty Versatility
	enchants[104395] = {74708} -- Enchant Chest - Glorious Stats
	enchants[104397] = {74709} -- Enchant Chest - Superior Stamina
	enchants[104398] = {74710} -- Enchant Cloak - Accuracy
	enchants[104401] = {74711} -- Enchant Cloak - Greater Protection
	enchants[104403] = {74712} -- Enchant Cloak - Superior Intellect
	enchants[104404] = {74713} -- Enchant Cloak - Superior Critical Strike
	enchants[104407] = {74715} -- Enchant Boots - Greater Haste
	enchants[104408] = {74716} -- Enchant Boots - Greater Precision
	enchants[104409] = {74717} -- Enchant Boots - Blurred Speed
	enchants[104414] = {74718} -- Enchant Boots - Pandaren's Step
	enchants[104416] = {74719} -- Enchant Gloves - Greater Haste
	enchants[104417] = {74720} -- Enchant Gloves - Superior Haste
	enchants[104419] = {74721} -- Enchant Gloves - Super Strength
	enchants[104420] = {74722} -- Enchant Gloves - Superior Mastery
	enchants[104425] = {74723} -- Enchant Weapon - Windsong
	enchants[104427] = {74724} -- Enchant Weapon - Jade Spirit
	enchants[104430] = {74725} -- Enchant Weapon - Elemental Force
	enchants[104434] = {74726} -- Enchant Weapon - Dancing Steel
	enchants[104440] = {74727} -- Enchant Weapon - Colossus
	enchants[104442] = {74728} -- Enchant Weapon - River's Song
	enchants[104445] = {74729} -- Enchant Off-Hand - Major Intellect
	enchants[130758] = {89737} -- Enchant Shield - Greater Parry
end

local vellums = {
	[ARMOR] = {
		[0] = {38682, 37602, 43145}, -- Armor Vellum, II, III
		[35] = {37602, 43145}, -- Armor Vellum II, III
		[60] = {43145}, -- Armor Vellum III
	},
	[WEAPON] = {
		[0] = {39349, 39350, 43146}, -- Weapon Vellum, II, III
		[35] = {39350, 43146}, -- Weapon Vellum II, III
		[60] = {43146}, -- Weapon Vellum III
	},
}

local universalVellum = {38682}

function module:GetEnchant(spellID)
	local data = enchants[spellID]
	if not data then
		return
	end
	if isMists then
		return data[1], universalVellum
	end
	return data[1], vellums[data[2]][data[3]], data[3], data[2]
end