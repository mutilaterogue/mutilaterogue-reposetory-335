-- Трансмогрификация: общие данные (ретейл: Blizzard_TransmogShared).
-- Опкоды (имена; запрос и ответ называются по-разному - клиент получает и свой аддон-шёпот):
--   "TMOG_GET_STATE" -> "TMOG_STATE" : "slot/itemId,..."        текущие трансмоги
--   "TMOG_APPLY" : "slot/itemId,..." (0 = вернуть облик) -> "TMOG_RESULT" : ok(1/0) : имя строки ошибки : itemId
--   "TMOG_OPEN" / "TMOG_CLOSE"  окно у NPC открывает/закрывает сервер
--   "APPEAR_GET_PAGE" ... : "T" : 20 -> "APPEAR_PAGE" ... : "T"   облики (appearance_collection.cpp)

TransmogUI = TransmogUI or {};

TransmogUI.OP_GET_STATE, TransmogUI.OP_STATE = "TMOG_GET_STATE", "TMOG_STATE";
TransmogUI.OP_APPLY, TransmogUI.OP_RESULT = "TMOG_APPLY", "TMOG_RESULT";
TransmogUI.OP_OPEN, TransmogUI.OP_CLOSE = "TMOG_OPEN", "TMOG_CLOSE";
TransmogUI.OP_GET_PAGE, TransmogUI.OP_PAGE = "APPEAR_GET_PAGE", "APPEAR_PAGE";
-- наряды, ситуации, свои комплекты (server/transmog_outfits.cpp), наборы (server/transmog_sets.cpp)
TransmogUI.OP_OUTFITS_GET, TransmogUI.OP_OUTFIT, TransmogUI.OP_OUTFITS_END = "TMOG_OUTFITS_GET", "TMOG_OUTFIT", "TMOG_OUTFITS_END";
TransmogUI.OP_OUTFIT_SAVE, TransmogUI.OP_OUTFIT_EQUIP, TransmogUI.OP_OUTFIT_RENAME = "TMOG_OUTFIT_SAVE", "TMOG_OUTFIT_EQUIP", "TMOG_OUTFIT_RENAME";
TransmogUI.OP_OUTFIT_DEL, TransmogUI.OP_OUTFIT_BUY, TransmogUI.OP_OUTFIT_SIT = "TMOG_OUTFIT_DEL", "TMOG_OUTFIT_BUY", "TMOG_OUTFIT_SIT";
TransmogUI.OP_OUTFIT_ACTIVE = "TMOG_OUTFIT_ACTIVE";
TransmogUI.OP_CSETS_GET, TransmogUI.OP_CSET, TransmogUI.OP_CSETS_END = "TMOG_CSETS_GET", "TMOG_CSET", "TMOG_CSETS_END";
TransmogUI.OP_CSET_SAVE, TransmogUI.OP_CSET_DEL = "TMOG_CSET_SAVE", "TMOG_CSET_DEL";
TransmogUI.OP_SETS_GET, TransmogUI.OP_SET, TransmogUI.OP_SETS_END = "TMOG_SETS_GET", "TMOG_SET", "TMOG_SETS_END";

TransmogUI.GRID_COLUMNS, TransmogUI.GRID_ROWS = 5, 4;   -- ретейл: 5x4 карточек 100x132, отступы 20
TransmogUI.MODEL_WIDTH, TransmogUI.MODEL_HEIGHT, TransmogUI.MODEL_SPACE_X, TransmogUI.MODEL_SPACE_Y = 100, 132, 20, 20;

-- раскладка как в ретейле: образы | персонаж | коллекция
TransmogUI.LEFT_X1, TransmogUI.LEFT_X2 = 4, 264;
TransmogUI.CENTER_X1, TransmogUI.CENTER_X2 = 266, 726;
TransmogUI.RIGHT_X1, TransmogUI.RIGHT_X2 = 728, 1196;
TransmogUI.PANEL_TOP, TransmogUI.PANEL_BOTTOM = -22, -716;

TransmogUI.NUM_OUTFIT_BUTTONS = 13;   -- OutfitList 650 / запись 48
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

-- текст ошибки сервера: имя глобальной строки ретейла (Blizzard_TransmogStrings.lua), "%s" - ссылка на предмет
function TransmogUI.GetErrorText(errorName, errorItem)
	if not errorName or errorName == "" then
		return nil;
	end
	local text = _G[errorName] or errorName;
	if text:find("%%s") then
		local itemId = tonumber(errorItem);
		local name = itemId and itemId > 0 and (select(2, GetItemInfo(itemId)) or ("item:" .. itemId)) or "";
		text = text:format(name);
	elseif text:find("%%d") then
		text = text:format(tonumber(errorItem) or 0);
	end
	return text;
end

-- ячейка экипировки для облика предмета (наборы, свои комплекты)
TransmogUI.SLOT_BY_EQUIPLOC = {
	INVTYPE_HEAD = 1, INVTYPE_SHOULDER = 3, INVTYPE_CLOAK = 15, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_BODY = 4,
	INVTYPE_TABARD = 19, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8,
	INVTYPE_WEAPON = 16, INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 16, INVTYPE_WEAPONOFFHAND = 17,
	INVTYPE_SHIELD = 17, INVTYPE_HOLDABLE = 17, INVTYPE_RANGED = 18, INVTYPE_RANGEDRIGHT = 18, INVTYPE_THROWN = 18,
};

function TransmogUI.GetItemSlot(itemId)
	local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemId);
	if not equipLoc then
		TransmogUI.RequestItem(itemId);
		return nil;
	end
	return TransmogUI.SLOT_BY_EQUIPLOC[equipLoc];
end

-- "slot/itemId,..." <-> { [slot] = itemId }
function TransmogUI.FormatSlots(slots)
	local list = {};
	for _, info in ipairs(TransmogUI.SLOTS) do
		if slots[info.id] then
			table.insert(list, info.id .. "/" .. slots[info.id]);
		end
	end
	return table.concat(list, ",");
end

-- облик, который сейчас показан на персонаже: изменения > трансмогрификация > надетый предмет
function TransmogUI.DisplayedLooks(frame, includeEquipped)
	local looks = {};
	for _, info in ipairs(TransmogUI.SLOTS) do
		local pending = frame.pending[info.id];
		local itemId;
		if pending ~= nil then
			itemId = pending ~= 0 and pending or (includeEquipped and GetInventoryItemID("player", info.id)) or nil;
		elseif frame.applied[info.id] then
			itemId = frame.applied[info.id];
		elseif includeEquipped then
			itemId = GetInventoryItemID("player", info.id);
		end
		if itemId then
			looks[info.id] = itemId;
		end
	end
	return looks;
end

-- примерить облики на надетые предметы (в очередь изменений); replaceAll: остальные ячейки вернуть к предмету
function TransmogUI.LoadLooks(frame, looks, replaceAll)
	if replaceAll then
		wipe(frame.pending);
	end
	for _, info in ipairs(TransmogUI.SLOTS) do
		local slotId = info.id;
		local equipped = GetInventoryItemID("player", slotId);
		local itemId = looks[slotId];
		if equipped then
			if itemId then
				if itemId == equipped then
					frame.pending[slotId] = frame.applied[slotId] and 0 or nil;
				elseif itemId == frame.applied[slotId] then
					frame.pending[slotId] = nil;
				else
					frame.pending[slotId] = itemId;
				end
			elseif replaceAll and frame.applied[slotId] then
				frame.pending[slotId] = 0;
			end
		end
	end
	TransmogUI.UpdateSlots(frame);
	TransmogUI.UpdatePreview(frame);
	TransmogUI.UpdateGrid(frame);
end

-- название комплекта (ItemSet.dbc) из подсказки предмета: строка "Название (0/5)"
TransmogUI.setNames = {};
function TransmogUI.GetSetName(setId, itemId)
	if TransmogUI.setNames[setId] then
		return TransmogUI.setNames[setId];
	end
	local tooltip = TransmogUI.itemQueryTooltip;
	tooltip:SetOwner(UIParent, "ANCHOR_NONE");
	tooltip:SetHyperlink("item:" .. itemId);
	local name;
	for i = 2, tooltip:NumLines() do
		local line = _G["TransmogQueryTooltipTextLeft" .. i];
		local text = line and line:GetText();
		local found = text and text:match("^(.-) %(%d+/%d+%)$");
		if found and found ~= "" then
			name = found;
			break;
		end
	end
	tooltip:Hide();
	if name then
		TransmogUI.setNames[setId] = name;
	end
	return name;
end

-- модели карточек: облик ставится после загрузки модели, поэтому одевание повторяется
TransmogUI.REDRESS_DELAYS = { 0.1, 0.3, 0.6, 1.0, 2.0 };

-- камера моделей в сетке - та же, что во «Внешнем виде» (WCollections по расе/полу/типу предмета)
local CATEGORY_INVTYPE = {
	[1] = "INVTYPE_HEAD", [2] = "INVTYPE_SHOULDER", [3] = "INVTYPE_CLOAK", [4] = "INVTYPE_CHEST", [5] = "INVTYPE_BODY",
	[6] = "INVTYPE_TABARD", [7] = "INVTYPE_WRIST", [8] = "INVTYPE_HAND", [9] = "INVTYPE_WAIST", [10] = "INVTYPE_LEGS",
	[11] = "INVTYPE_FEET",
};
local DEFAULT_WEAPON_CAMERA = { 0.6, 0, -0.05, 0.6 };
local DEFAULT_CAMERA = { 0, 0, 0, 0 };

function TransmogUI.GetCamera(category, itemId)
	if WardrobeGetCamera then
		return WardrobeGetCamera(category, itemId);
	end
	if category and category >= 20 then
		return (WARDROBE_WEAPON_CAMERAS and (WARDROBE_WEAPON_CAMERAS[category] or WARDROBE_WEAPON_CAMERAS.default)) or DEFAULT_WEAPON_CAMERA;
	end
	if WCollections and WCollections.Cameras and WCollections.GetCharacterCameraID then
		local invType = itemId and select(9, GetItemInfo(itemId));
		if not invType or invType == "" then
			invType = CATEGORY_INVTYPE[category];
		end
		if invType then
			local cam = WCollections.Cameras[WCollections:GetCharacterCameraID(invType)];
			if cam then
				return cam;
			end
		end
	end
	return DEFAULT_CAMERA;
end
