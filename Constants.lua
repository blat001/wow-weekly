local ADDON_NAME = "WoWWeekly"
local ADDON_VERSION = "1.4.1"

local Constants = {
	ADDON_NAME = ADDON_NAME,
	ADDON_VERSION = ADDON_VERSION,

	-- Tracker IDs (registry keys)
	TRACKER_DELVES = "delves",
	TRACKER_BOUNTYMAP = "bountymap",
	TRACKER_COFFERKEYS = "cofferkeys",
	TRACKER_COFFERKEYSHARDS = "cofferkeyshards",
	TRACKER_GILDEDSTASH = "gildedstash",
	TRACKER_PROFESSION1 = "profession1",
	TRACKER_PROFESSION1_TREATISE = "profession1treatise",
	TRACKER_PROFESSION2 = "profession2",
	TRACKER_PROFESSION2_TREATISE = "profession2treatise",
	TRACKER_READYTOCRAFT = "readytocraft",
	TRACKER_MYTHICPLUS = "mythicplus",
	TRACKER_MPLUS_WEEK = "mplus_week",
	TRACKER_MPLUS_KEY = "mplus_key",
	TRACKER_RAID = "raid",
	TRACKER_RAID_LFR = "raidprogress_lfr",
	TRACKER_RAID_NORMAL = "raidprogress_normal",
	TRACKER_RAID_HEROIC = "raidprogress_heroic",
	TRACKER_RAID_MYTHIC = "raidprogress_mythic",
	TRACKER_PREY_NORMAL = "preynormal",
	TRACKER_PREY_HARD = "preyhard",
	TRACKER_PREY_NIGHTMARE = "preynightmare",
	TRACKER_METAQUEST = "metaquest",
	TRACKER_TURNBACKSURGE = "turnbacksurge",
	TRACKER_PURGINGVAULTS = "purgingvaults",
	TRACKER_COILEDISLE_WORLDBOSS = "coiledisle_worldboss",
	TRACKER_TIMEWALKING = "timewalking",

	-- Delves (Great Vault world track)
	DELVE_VAULT_MAX = 8,
	DELVE_HERO_THRESHOLD = 4,
	DELVE_MIN_TIER = 8,

	-- Mythic+ (Great Vault M+ track). Slots unlock at 1/4/8 runs;
	-- +10 and above fills a slot with Myth-track gear.
	MPLUS_VAULT_MAX = 8,
	MPLUS_MYTH_THRESHOLD = 4,
	MPLUS_MIN_LEVEL = 10,

	-- Midnight Season 2 begins with the US weekly reset on Aug 18, 2026 at
	-- 15:00 UTC. During the preceding 12.1 pre-season week, Mythic+ and
	-- Bountiful Delves are unavailable (Mythic 0 and ordinary Delves remain).
	MIDNIGHT_SEASON_2_START = 1787065200,
	MIDNIGHT_SEASON_KEY = "midnight-2",

	-- Raid (Great Vault raid track). Slots unlock at 2/4/6 boss kills.
	RAID_VAULT_MAX = 6,
	RAID_FULL_THRESHOLD = 6,
	CURRENT_RAID_NAME = "Venomous Abyss",
	CURRENT_RAID_BOSSES = 8,

	-- A Great Vault source stops being worth doing (for GEAR) once a character is
	-- geared a full tier above what it rewards. Judged by AVERAGE equipped item
	-- level, NOT a single slot (a low slot may be a deliberate BiS piece).
	-- Midnight Season 2 vault ceilings: delves give Hero-track gear (top 321),
	-- while Myth gear starts at 318 and normally tops out at 334 (exceptional
	-- raid rewards can reach 337). Rule: only skip delves once you are in Myth
	-- gear (avg >= Myth floor, 318). M+ and raid give the best gear in
	-- the game, so they never auto-skip. 0 = never skip.
	VAULT_STOP_DELVE = 318,  -- skip delves once average ilvl reaches Myth gear
	VAULT_STOP_MPLUS = 0,    -- never (M+ gives the best dungeon gear)
	VAULT_STOP_RAID  = 0,    -- never (raid gives the best gear)

	-- Currency IDs (CONFIRM IN-GAME with /ww find)
	CURRENCY_RESTORED_COFFER_KEY = 3028,
	CURRENCY_COFFER_KEY_SHARD = 3310,
	-- Midnight Season 2 Mistcrests. Crafting Hero or Myth gear requires 80 of
	-- the corresponding crest; the Ready to Craft row can be configured for
	-- either track.
	CURRENCY_HERO_CREST = 3445,
	CURRENCY_MYTH_CREST = 3446,
	CREST_CRAFT_THRESHOLD = 80,
	MYTH_CREST_CRAFT_THRESHOLD = 80, -- compatibility alias

	-- Coffer Key Shard weekly earn cap
	COFFER_SHARD_WEEKLY_CAP = 600,

	-- Shards auto-combine into a Restored Coffer Key when you enter a delve
	SHARDS_PER_KEY = 100,

	-- Trovehunter's Bounty. The hidden weekly quest flags when the map has been
	-- used. Always check the physical Season 2 item first so a map still sitting
	-- in bags reads "In Bags" even if the quest flag is unexpectedly stale.
	QUEST_BOUNTY_LOOTED = 86371,
	ITEM_BOUNTY_MAP = 265714,  -- Trovehunter's Bounty (Midnight Season 2)
	ITEM_BOUNTY_MAPS = { 265714, 252415 }, -- Season 2 + legacy Season 1 item

	-- Weekly profession knowledge quests (Midnight "mn-profession-weeklies" in
	-- SavedInstances), keyed by the BASE profession skill-line ID returned by
	-- GetProfessionInfo(). Gathering professions rotate among several possible
	-- weeklies, so each entry is a LIST and the weekly is "done" if ANY is done.
	-- NOTE: these are expansion-specific; update them each expansion.
	PROFESSION_WEEKLY_QUESTS = {
		[171] = { 93690 },                              -- Alchemy
		[164] = { 93691 },                              -- Blacksmithing
		[202] = { 93692 },                              -- Engineering
		[773] = { 93693 },                              -- Inscription
		[755] = { 93694 },                              -- Jewelcrafting
		[165] = { 93695 },                              -- Leatherworking
		[197] = { 93696 },                              -- Tailoring
		[333] = { 93697, 93698, 93699 },                -- Enchanting
		[182] = { 93700, 93701, 93702, 93703, 93704 },  -- Herbalism
		[186] = { 93705, 93706, 93707, 93708, 93709 },  -- Mining
		[393] = { 93710, 93711, 93712, 93713, 93714 },  -- Skinning
	},

	-- Weekly profession TREATISE quests (Midnight "Thalassian Treatise"),
	-- consumed once/week for knowledge. Quest IDs from SavedInstances
	-- (Modules/Progress.lua "mn-thalassian-treatise"), keyed by skill-line ID.
	-- NOTE: these are expansion-specific; update them each expansion.
	PROFESSION_TREATISE_QUESTS = {
		[171] = { 95127 }, -- Alchemy
		[164] = { 95128 }, -- Blacksmithing
		[333] = { 95129 }, -- Enchanting
		[202] = { 95138 }, -- Engineering
		[182] = { 95130 }, -- Herbalism
		[773] = { 95131 }, -- Inscription
		[755] = { 95133 }, -- Jewelcrafting
		[165] = { 95134 }, -- Leatherworking
		[186] = { 95135 }, -- Mining
		[393] = { 95136 }, -- Skinning
		[197] = { 95137 }, -- Tailoring
	},

	-- Prey (Midnight weekly hunt). Each difficulty is its own weekly goal of 4
	-- distinct kills, tracked by counting how many quests from a rotating pool
	-- are flagged complete this week. Quest IDs from SavedInstances
	-- (Modules/Progress.lua "mn-prey-normal/hard/nightmare", expansion 11).
	-- NOTE: expansion-specific; update each expansion.
	PREY_WEEKLY_GOAL = 4,
	PREY_NORMAL_QUESTS = {
		91095, 91096, 91097, 91098, 91099, 91100, 91101, 91102, 91103, 91104,
		91105, 91106, 91107, 91108, 91109, 91110, 91111, 91112, 91113, 91114,
		91115, 91116, 91117, 91118, 91119, 91120, 91121, 91122, 91123, 91124,
	},
	PREY_HARD_QUESTS = {
		91210, 91212, 91214, 91216, 91218, 91220, 91222, 91224, 91226, 91228,
		91230, 91232, 91234, 91236, 91238, 91240, 91242, 91243, 91244, 91245,
		91246, 91247, 91248, 91249, 91250, 91251, 91252, 91253, 91254, 91255,
	},
	PREY_NIGHTMARE_QUESTS = {
		91211, 91213, 91215, 91217, 91219, 91221, 91223, 91225, 91227, 91229,
		91231, 91233, 91235, 91237, 91239, 91241, 91256, 91257, 91258, 91259,
		91260, 91261, 91262, 91263, 91264, 91265, 91266, 91267, 91268, 91269,
	},

	-- Midnight Meta Quest ("the weekly quest"). SavedInstances calls this group
	-- "mn-meta-quest" with type = "any". The character CHOOSES one objective;
	-- the chosen variant becomes a quest in their log with progress. We detect
	-- whichever pool quest is in the log and show its name + progress (e.g.
	-- "Delves 2/3"), falling back to a completed-flag check. IDs from
	-- SavedInstances Modules/Progress.lua (expansion 11).
	META_QUEST_POOL = {
		93766,  -- World Quests
		93767,  -- Arcantina
		93769,  -- Housing
		93889,  -- Saltheril's Soiree
		93890,  -- Abundance
		93891,  -- Legends of the Haranir
		93892,  -- Stormarion Assault
		93909,  -- Delves
		93910,  -- Prey
		93911,  -- Dungeons
		93912,  -- Raid
		93913,  -- World Boss
		94457,  -- Battlegrounds
		95842,  -- Void Assaults
		98172,  -- Trailing Xal'atath (12.1 freeform weekly)
		98232,  -- Midnight: Vaults of Atal'Utek (Coiled Isle)
	},

	-- Short display names for the chosen meta-quest variant, so the row can show
	-- e.g. "Delves 2/3" instead of just "Done".
	META_QUEST_NAMES = {
		[93766] = "World Quests",
		[93767] = "Arcantina",
		[93769] = "Housing",
		[93889] = "Soiree",
		[93890] = "Abundance",
		[93891] = "Haranir",
		[93892] = "Stormarion",
		[93909] = "Delves",
		[93910] = "Prey",
		[93911] = "Dungeons",
		[93912] = "Raid",
		[93913] = "World Boss",
		[94457] = "Battlegrounds",
		[95842] = "Void Assaults",
		[98172] = "Trailing Xal'atath",
		[98232] = "Coiled Isle",
	},

	-- Max-level Timewalking weekly quests ("A <X> Path Through Time"). Do not
	-- include the similarly named "Journey Through Time" leveling quests: those
	-- award the leveling goodie bag and are a different objective/reward track.
	-- Midnight replaced the older expansion-era IDs with this current set.
	TIMEWALKING_POOL = {
		93607,  -- An Original Path Through Time (Classic)
		93608,  -- A Burning Path Through Time (TBC)
		93610,  -- A Frozen Path Through Time (WotLK)
		93611,  -- A Shattered Path Through Time (Cataclysm)
		93612,  -- A Shrouded Path Through Time (Mists of Pandaria)
		93613,  -- A Savage Path Through Time (Warlords of Draenor)
		93614,  -- A Fel Path Through Time (Legion)
		93627,  -- A Scarred Path Through Time (Battle for Azeroth)
		93628,  -- A Shadowed Path Through Time (Shadowlands)
		93497,  -- A Soaring Path Through Time (Dragonflight)
	},

	QUEST_TURN_BACK_SURGE = 96995,
	QUEST_PURGING_VAULTS = 95520,
	QUEST_COILED_ISLE_WORLD_BOSS = 97128, -- Lair: Nymrissa Wavecaller

	-- Row groups for the tooltip, in display order. Each tracker declares a
	-- `group` (matching an id below) and an `order` for sorting within it.
	GROUPS = {
		{ id = "raidprogress", label = "Raid" },
		{ id = "mplus",       label = "Mythic+" },
		{ id = "rituals",     label = "Coiled Isle" },
		{ id = "weekly",      label = "Weekly Quest" },
		{ id = "prey",        label = "Prey" },
		{ id = "delves",      label = "Delves" },
		{ id = "professions", label = "Professions" },
		{ id = "vault",       label = "Great Vault" },
	},

	-- Colors
	COLOR_GREEN = "|cFF00FF00",
	COLOR_RED = "|cFFFF0000",
	COLOR_YELLOW = "|cFFFFFF00",
	COLOR_GRAY = "|cFF808080",
	COLOR_WHITE = "|cFFFFFFFF",
	COLOR_PURPLE = "|cFFA335EE",  -- epic / keystone color
	COLOR_GOLD = "|cFFFFD100",    -- Blizzard header gold (for in-cell sub-headings)
	COLOR_RESET = "|r",

	-- Glossy status "ball" textures (Blizzard COMMON indicators), inlined into
	-- tooltip cells for an at-a-glance colored-circle look. 14px tall.
	DOT_GREEN  = "|TInterface\\COMMON\\Indicator-Green:14|t",
	DOT_YELLOW = "|TInterface\\COMMON\\Indicator-Yellow:14|t",
	DOT_RED    = "|TInterface\\COMMON\\Indicator-Red:14|t",
	DOT_GRAY   = "|TInterface\\COMMON\\Indicator-Gray:14|t",
	CHECK_GREEN = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t",

	-- DB version
	DB_VERSION = 1,
}

function Constants.IsMidnightSeason2Active()
	return time() >= Constants.MIDNIGHT_SEASON_2_START
end

-- Persistent per-character activity affinity. Tracker state resets weekly, but
-- this profile lives beside it on the character record. One active week adds a
-- point; unused history decays by 25% per reset so retired activities naturally
-- stop being recommended. Repeated scans in one week only earn one point.
local function ActivityPeriod(charState)
	if charState and (charState.resetPeriodId or 0) > 0 then
		return charState.resetPeriodId
	end
	local untilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
	local seconds = untilReset and untilReset() or 0
	return math.floor((time() + seconds) / 604800)
end

function Constants.GetActivityAffinity(charState, activity)
	local profile = charState and charState.activityProfile
	local entry = profile and profile[activity]
	if not entry then return 0 end
	local elapsed = math.max(0, ActivityPeriod(charState) - (entry.scorePeriod or ActivityPeriod(charState)))
	return (entry.score or 0) * (0.75 ^ elapsed)
end

function Constants.RecordActivity(charState, activity, detail)
	if not (charState and activity) then return end
	charState.activityProfile = charState.activityProfile or {}
	local period = ActivityPeriod(charState)
	local entry = charState.activityProfile[activity] or {}
	charState.activityProfile[activity] = entry
	if entry.creditedPeriod ~= period then
		entry.score = math.min(4, Constants.GetActivityAffinity(charState, activity) + 1)
		entry.scorePeriod = period
		entry.creditedPeriod = period
		entry.activeWeeks = (entry.activeWeeks or 0) + 1
	end
	entry.lastActivePeriod = period
	if detail and (not entry.highest or detail > entry.highest) then entry.highest = detail end
end

-- Equipment slots that carry item level (excludes shirt=4 and tabard=19).
local ILVL_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

-- Lowest item level among currently equipped gear. Comparing a reward to this
-- (rather than the average) tells us whether it could upgrade ANY slot, which
-- fixes the "high average but one weak slot" case.
function Constants.GetMinEquippedIlvl()
	local getIlvl = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
	if not getIlvl then return 0 end
	local minIlvl
	for _, slot in ipairs(ILVL_SLOTS) do
		local link = GetInventoryItemLink("player", slot)
		if link then
			local ok, ilvl = pcall(getIlvl, link)
			if ok and ilvl and ilvl > 0 then
				if not minIlvl or ilvl < minIlvl then minIlvl = ilvl end
			end
		end
	end
	return minIlvl or 0
end

-- Highest reward item level offered by a set of Great Vault activities. Tries
-- the forward-looking example reward (works for unfilled slots) and the actual
-- filled-slot reward. Returns 0 if nothing could be read.
function Constants.MaxRewardIlvl(activities)
	if type(activities) ~= "table" then return 0 end
	local getIlvl = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
	local maxIlvl = 0
	for _, a in ipairs(activities) do
		if C_WeeklyRewards and C_WeeklyRewards.GetExampleRewardItemHyperlinks and a.id and getIlvl then
			-- May return multiple hyperlinks (item, currency); pass each whole
			-- link straight to GetDetailedItemLevelInfo, like the Blizzard vault UI.
			local res = { pcall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, a.id) }
			if res[1] then
				for i = 2, #res do
					local link = res[i]
					if type(link) == "string" and link ~= "" then
						local iok, ilvl = pcall(getIlvl, link)
						if iok and ilvl and ilvl > maxIlvl then maxIlvl = ilvl end
					end
				end
			end
		end
		if C_WeeklyRewards and C_WeeklyRewards.GetActivityRewards and a.type and a.index then
			local ok, rewards = pcall(C_WeeklyRewards.GetActivityRewards, a.type, a.index)
			if ok and type(rewards) == "table" then
				for _, r in ipairs(rewards) do
					if r.itemLevel and r.itemLevel > maxIlvl then maxIlvl = r.itemLevel end
				end
			end
		end
	end
	return maxIlvl
end

-- Recommender grouping: collapse related incomplete to-dos into a single
-- entry, e.g. "Delves (Vault, Gilded, Bounty Map)". Members are listed in
-- display order; only the INCOMPLETE ones show (completed members drop out),
-- and the whole group disappears once everything in it is done. Any
-- countsForRecommend tracker not listed here appears standalone via GetAction.
--
-- A member shows its fixed `short` when its tracker is incomplete. If the
-- tracker instead implements RecTags(charState), the group collects those tags
-- (deduped, in order) rather than the `short` -- this is how Professions
-- collapses to "Professions (Weekly, Treatise)" across both prof slots.
Constants.REC_GROUPS = {
	{
		label = "Delves",
		members = {
			{ id = Constants.TRACKER_DELVES,      short = "Vault" },
			{ id = Constants.TRACKER_GILDEDSTASH, short = "Gilded" },
			{ id = Constants.TRACKER_BOUNTYMAP,   short = "Bounty Map" },
		},
	},
	{
		label = "Professions",
		members = {
			{ id = Constants.TRACKER_PROFESSION1 },  -- tags via RecTags
			{ id = Constants.TRACKER_PROFESSION2 },
		},
	},
}

-- True if a vault source is still worth doing for this character, judged by
-- AVERAGE equipped item level. stopIlvl is the average at/above which the source
-- no longer helps (you are geared a tier above it). stop <= 0 means always worth.
function Constants.VaultWorthDoing(charState, stopIlvl)
	if not stopIlvl or stopIlvl <= 0 then return true end
	local avg = charState and charState.ilvl or 0
	if avg <= 0 then return true end
	return avg < stopIlvl
end

_G[ADDON_NAME .. "Constants"] = Constants
