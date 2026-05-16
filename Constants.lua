local _, Shatter = ...

local Constants = {}
Shatter.Constants = Constants
Shatter.RegisterModule("Constants", Constants)

Constants.SPELL_DISENCHANT = 13262

Constants.QUALITY_UNCOMMON = 2
Constants.QUALITY_RARE = 3
Constants.QUALITY_EPIC = 4
Constants.DEFAULT_MAX_QUALITY = Constants.QUALITY_RARE

Constants.QUEUE_ORDER = {
    BAG_SLOT = "BAG_SLOT",
    FIFO = "FIFO",
    LIFO = "LIFO",
}

Constants.QUEUE_ORDER_LABELS = {
    BAG_SLOT = "Bag / Slot",
    FIFO = "First In, First Out",
    LIFO = "Last In, First Out",
}

Constants.WINDOW = {
    DEFAULT_WIDTH = 540,
    DEFAULT_HEIGHT = 340,
    MIN_WIDTH = 520,
    MIN_HEIGHT = 320,
    MAX_WIDTH = 900,
    MAX_HEIGHT = 650,
    MIN_SCALE = 0.75,
    MAX_SCALE = 1.5,
}

Constants.QUALITY_LABELS = {
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Epic",
}

Constants.ITEM_CLASS_WEAPON = 2
Constants.ITEM_CLASS_ARMOR = 4

Constants.DISENCHANT_EQUIP_LOCS = {
    INVTYPE_HEAD = true,
    INVTYPE_NECK = true,
    INVTYPE_SHOULDER = true,
    INVTYPE_BODY = true,
    INVTYPE_CHEST = true,
    INVTYPE_ROBE = true,
    INVTYPE_WAIST = true,
    INVTYPE_LEGS = true,
    INVTYPE_FEET = true,
    INVTYPE_WRIST = true,
    INVTYPE_HAND = true,
    INVTYPE_FINGER = true,
    INVTYPE_TRINKET = true,
    INVTYPE_CLOAK = true,
    INVTYPE_WEAPON = true,
    INVTYPE_SHIELD = true,
    INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_HOLDABLE = true,
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true,
    INVTYPE_RELIC = true,
}

Constants.MODES = {
    SOLO = "SOLO",
    MAIL = "MAIL",
    RAID = "RAID",
}

Constants.STATUS = {
    READY = "Ready",
    NO_ITEMS = "No eligible items",
    WAITING_LOOT = "Waiting for loot",
    WAITING_RESULT = "Waiting for disenchant result",
    INVENTORY_FULL = "Inventory full",
    MISSING_ENCHANTING = "Missing enchanting profession",
    MAILBOX_REQUIRED = "Mailbox required",
    TRADE_REQUIRED = "Trade window required",
    ITEM_MISSING = "Item moved or missing",
    ITEM_SKIPPED = "Item skipped",
    ITEM_IGNORED = "Item ignored",
    DISENCHANT_FAILED = "Disenchant failed or no result detected",
    DONE = "Done",
}

Constants.MATERIAL_ITEM_IDS = {
    [10938] = true, -- Lesser Magic Essence
    [10939] = true, -- Greater Magic Essence
    [10940] = true, -- Strange Dust
    [10978] = true, -- Small Glimmering Shard
    [10998] = true, -- Lesser Astral Essence
    [11082] = true, -- Greater Astral Essence
    [11083] = true, -- Soul Dust
    [11084] = true, -- Large Glimmering Shard
    [11134] = true, -- Lesser Mystic Essence
    [11135] = true, -- Greater Mystic Essence
    [11137] = true, -- Vision Dust
    [11138] = true, -- Small Glowing Shard
    [11139] = true, -- Large Glowing Shard
    [11174] = true, -- Lesser Nether Essence
    [11175] = true, -- Greater Nether Essence
    [11176] = true, -- Dream Dust
    [11177] = true, -- Small Radiant Shard
    [11178] = true, -- Large Radiant Shard
    [14343] = true, -- Small Brilliant Shard
    [14344] = true, -- Large Brilliant Shard
    [16202] = true, -- Lesser Eternal Essence
    [16203] = true, -- Greater Eternal Essence
    [16204] = true, -- Illusion Dust
    [20725] = true, -- Nexus Crystal
    [22445] = true, -- Arcane Dust
    [22446] = true, -- Greater Planar Essence
    [22447] = true, -- Lesser Planar Essence
    [22448] = true, -- Small Prismatic Shard
    [22449] = true, -- Large Prismatic Shard
    [22450] = true, -- Void Crystal
}

Constants.NON_DISENCHANTABLE = {
    -- Phase 0/2 should expand this denylist with verified TBC exceptions.
}
