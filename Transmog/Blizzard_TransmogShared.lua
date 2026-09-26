-- Трансмогрификация: общие данные (ретейл: Blizzard_TransmogShared).
-- Опкоды (имена; запрос и ответ называются по-разному - клиент получает и свой аддон-шёпот):
--   "TMOG_GET_STATE" -> "TMOG_STATE" : "slot/itemId,..."        текущие трансмоги
--   "TMOG_APPLY" : "slot/itemId,..." (0 = вернуть облик) -> "TMOG_RESULT" : ok(1/0) : message
--   "TMOG_OPEN" / "TMOG_CLOSE"  окно у NPC открывает/закрывает сервер
--   "APPEAR_GET_PAGE" ... : "T" : 24 -> "APPEAR_PAGE" ... : "T"   облики (appearance_collection.cpp)

TransmogUI = TransmogUI or {};

TransmogUI.OP_GET_STATE, TransmogUI.OP_STATE = "TMOG_GET_STATE", "TMOG_STATE";
TransmogUI.OP_APPLY, TransmogUI.OP_RESULT = "TMOG_APPLY", "TMOG_RESULT";
TransmogUI.OP_OPEN, TransmogUI.OP_CLOSE = "TMOG_OPEN", "TMOG_CLOSE";
TransmogUI.OP_GET_PAGE, TransmogUI.OP_PAGE = "APPEAR_GET_PAGE", "APPEAR_PAGE";

TransmogUI.GRID_COLUMNS, TransmogUI.GRID_ROWS = 6, 4;
TransmogUI.MODEL_WIDTH, TransmogUI.MODEL_HEIGHT, TransmogUI.MODEL_SPACE_X, TransmogUI.MODEL_SPACE_Y = 68, 86, 9, 12;

-- раскладка как в ретейле: образы | персонаж | коллекция
TransmogUI.LEFT_X1, TransmogUI.LEFT_X2 = 4, 264;
TransmogUI.CENTER_X1, TransmogUI.CENTER_X2 = 266, 726;
TransmogUI.RIGHT_X1, TransmogUI.RIGHT_X2 = 728, 1196;
TransmogUI.PANEL_TOP, TransmogUI.PANEL_BOTTOM = -22, -716;

TransmogUI.NUM_OUTFIT_BUTTONS = 14;
TransmogUI.MAX_OUTFITS = 30;

-- slot id, category (appearance_collection.cpp), side on the character
TransmogUI.SLOTS = {
	{ id = 1,  slot = "HeadSlot",          category = 1,  side = "LEFT",   name = "Голова" },
	{ id = 3,  slot = "ShoulderSlot",      category = 2,  side = "LEFT",   name = "Плечи" },
	{ id = 15, slot = "BackSlot",          category = 3,  side = "LEFT",   name = "Спина" },
	{ id = 5,  slot = "ChestSlot",         category = 4,  side = "LEFT",   name = "Грудь" },
	{ id = 4,  slot = "ShirtSlot",         category = 5,  side = "LEFT",   name = "Рубашка" },
	{ id = 19, slot = "TabardSlot",        category = 6,  side = "LEFT",   name = "Гербовая накидка" },
	{ id = 9,  slot = "WristSlot",         category = 7,  side = "LEFT",   name = "Запястья" },
	{ id = 10, slot = "HandsSlot",         category = 8,  side = "RIGHT",  name = "Кисти рук" },
	{ id = 6,  slot = "WaistSlot",         category = 9,  side = "RIGHT",  name = "Пояс" },
	{ id = 7,  slot = "LegsSlot",          category = 10, side = "RIGHT",  name = "Ноги" },
	{ id = 8,  slot = "FeetSlot",          category = 11, side = "RIGHT",  name = "Ступни" },
	{ id = 16, slot = "MainHandSlot",      weapon = true, side = "BOTTOM", name = "Правая рука" },
	{ id = 17, slot = "SecondaryHandSlot", weapon = true, side = "BOTTOM", name = "Левая рука" },
	{ id = 18, slot = "RangedSlot",        weapon = true, side = "BOTTOM", name = "Дальний бой" },
};
-- ретейловские атласы пустых слотов (Interface/Transmogrify)
TransmogUI.SLOT_UNASSIGNED_ATLAS = {
	[1] = "head", [3] = "shoulders", [15] = "back", [5] = "chest", [4] = "shirt", [19] = "tabard", [9] = "wrist",
	[10] = "hands", [6] = "waist", [7] = "legs", [8] = "feet", [16] = "mainHand", [17] = "offHand", [18] = "mainHand",
};
TransmogUI.SLOT_BY_ID = {};
for _, info in ipairs(TransmogUI.SLOTS) do
	TransmogUI.SLOT_BY_ID[info.id] = info;
end

TransmogUI.CLASS_IDS = {
	WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6,
	SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
};

-- 3.3.5: GetItemInfo gives the weapon type as text - map it to the item subclass id through the auction list
TransmogUI.WEAPON_SUBCLASS_ORDER = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 14, 15, 16, 18, 19, 20 };

function TransmogUI.GetWeaponSubclass(subTypeName)
	if not TransmogUI.weaponSubclassByName then
		TransmogUI.weaponSubclassByName = {};
		local names = { GetAuctionItemSubClasses(1) };
		for index, name in ipairs(names) do
			TransmogUI.weaponSubclassByName[name] = TransmogUI.WEAPON_SUBCLASS_ORDER[index];
		end
	end
	return TransmogUI.weaponSubclassByName[subTypeName];
end

-- category of the appearance list for an equipped item
function TransmogUI.GetItemCategory(slotInfo, itemLink)
	if not slotInfo.weapon then
		return slotInfo.category;
	end
	if not itemLink then
		return nil;
	end
	local _, _, _, _, _, _, subType, _, equipLoc = GetItemInfo(itemLink);
	if equipLoc == "INVTYPE_SHIELD" then
		return 40;
	elseif equipLoc == "INVTYPE_HOLDABLE" then
		return 41;
	end
	local subclass = TransmogUI.GetWeaponSubclass(subType);
	return subclass and (20 + subclass) or nil;
end

TransmogUI.itemQueryTooltip = CreateFrame("GameTooltip", "TransmogQueryTooltip", UIParent, "GameTooltipTemplate");
function TransmogUI.RequestItem(itemId)
	TransmogUI.itemQueryTooltip:SetOwner(UIParent, "ANCHOR_NONE");
	TransmogUI.itemQueryTooltip:SetHyperlink("item:" .. itemId);
	TransmogUI.itemQueryTooltip:Hide();
end

function TransmogUI.GetItemIcon(itemId)
	local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId);
	if not icon then
		TransmogUI.RequestItem(itemId);
	end
	return icon or "Interface\\Icons\\INV_Misc_QuestionMark";
end

function TransmogUI.CreateInset(parent, x1, y1, x2, y2)
	local inset = CreateFrame("Frame", nil, parent, "InsetFrameTemplate");
	inset:SetPoint("TOPLEFT", parent, "TOPLEFT", x1, y1);
	inset:SetPoint("BOTTOMRIGHT", parent, "TOPLEFT", x2, y2);
	return inset;
end

function TransmogUI.CreateLabel(parent, font, text)
	local label = parent:CreateFontString(nil, "OVERLAY", font);
	label:SetText(text);
	return label;
end

TransmogOutfits = TransmogOutfits or {};   -- { name, icon, slots = { [slotId] = itemId } } - на сервере позже