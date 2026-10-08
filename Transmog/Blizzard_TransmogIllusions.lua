-- Трансмогрификация: иллюзии оружия (ретейл: TransmogIllusionSlotMixin, Enum.TransmogType.Illusion).
-- Слоты иллюзий - под правой и левой рукой (TransmogIllusionSlotTemplate). Щелчок по слоту - в сетке справа
-- иллюзии на оружии этой руки, щелчок по карточке - иллюзия в очередь изменений; ПКМ по слоту - убрать иллюзию.
-- Сервер (server/transmog_illusions.cpp):
--   "TMOG_ILLUSIONS_GET" -> "TMOG_ILLUSIONS" : цена : "enchantId/spellId/collected,..."
--   применение - вторым аргументом "TMOG_APPLY" : облики : "slot/enchantId,..." (0 = убрать)
--   "TMOG_STATE" : облики : "slot/enchantId,..." - текущие иллюзии

local OP_ILLUSIONS_GET, OP_ILLUSIONS = "TMOG_ILLUSIONS_GET", "TMOG_ILLUSIONS";
local ILLUSION_SLOTS = { 16, 17 };

TransmogUI.illusions = nil;        -- { { id = enchantId, spell = spellId, collected, name, icon } }
TransmogUI.illusionCost = 0;

-- название иллюзии: рецепт «Чары для оружия - Мангуст» -> «Мангуст»
local function IllusionName(spellId)
	local name, _, icon = GetSpellInfo(spellId);
	if not name then
		return "?", "Interface\\Icons\\INV_Misc_QuestionMark";
	end
	return name:match("%s%-%s(.+)$") or name, icon;
end

function TransmogUI.GetIllusion(enchantId)
	for _, illusion in ipairs(TransmogUI.illusions or {}) do
		if illusion.id == enchantId then
			return illusion;
		end
	end
end

-- иллюзия, которая сейчас показана на оружии слота: изменение > наложенная
function TransmogUI.GetDisplayedIllusion(frame, slotId)
	local pending = frame.pendingIllusion[slotId];
	if pending ~= nil then
		return pending, true;
	end
	return frame.appliedIllusion[slotId] or 0, false;
end

TRANSMOG_ILLUSION_NO_EFFECT_ITEM = TRANSMOG_ILLUSION_NO_EFFECT_ITEM or "Этот предмет не может получить иллюзию.";

-- сервер: на какую руку иллюзия ложится (оружие со своим эффектом в модели - нет); nil - ещё не знаем
TransmogUI.illusionAllowed = nil;

function TransmogUI.SetIllusionAllowed(text)
	if text and text ~= "" then
		TransmogUI.illusionAllowed = TransmogUI.ParseSlots(text);   -- [16]/[17] = 1, запрещённые - нет в таблице
	end
end

-- у оружия свой эффект в модели (сервер запретил)
function TransmogUI.HasOwnEffect(slotId)
	local allowed = TransmogUI.illusionAllowed;
	return allowed ~= nil and GetInventoryItemLink("player", slotId) ~= nil and TransmogUI.IsMeleeWeapon(slotId) and not allowed[slotId];
end

-- оружие ближнего боя в руке (ретейл: только на него иллюзия)
function TransmogUI.IsMeleeWeapon(slotId)
	local link = GetInventoryItemLink("player", slotId);
	if not link then
		return false;
	end
	local _, _, _, _, _, itemType, _, _, equipLoc = GetItemInfo(link);
	local weaponType = GetAuctionItemClasses();   -- первый класс аукциона - «Оружие»
	return itemType == weaponType and (equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_2HWEAPON"
		or equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_WEAPONOFFHAND");
end

-- можно ли наложить иллюзию на то, что надето
function TransmogUI.CanHaveIllusion(slotId)
	return TransmogUI.IsMeleeWeapon(slotId) and not TransmogUI.HasOwnEffect(slotId);
end

-- строка предмета для примерки: оружие с иллюзией - "item:id:enchant"
function TransmogUI.PreviewItemString(frame, slotId, itemId)
	if slotId == 16 or slotId == 17 then
		local enchant = TransmogUI.GetDisplayedIllusion(frame, slotId);
		if enchant and enchant > 0 then
			return "item:" .. itemId .. ":" .. enchant;
		end
	end
	return "item:" .. itemId;
end

function TransmogUI.GetIllusionCost(frame)
	local cost = 0;
	for slotId, enchant in pairs(frame.pendingIllusion) do
		if enchant ~= 0 and enchant ~= frame.appliedIllusion[slotId] then
			cost = cost + (TransmogUI.illusionCost or 0);
		end
	end
	return cost;
end

---------------------------------------------------------------------------
-- слоты иллюзий
---------------------------------------------------------------------------
function TransmogIllusionSlot_OnLoad(self)
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	self:SetMotionScriptsWhileDisabled(true);
	local pending, saved = self.PendingFrame, self.SavedFrame;
	pending.AnimStart = TransmogAnim.Create(pending, TransmogAnim.SLOT_PENDING_START);
	pending.AnimLoop = TransmogAnim.Create(pending, TransmogAnim.SLOT_PENDING_LOOP, true);
	saved.Anim = TransmogAnim.Create(saved, TransmogAnim.SLOT_SAVED);
	saved.Anim:SetScript("OnFinished", function()
		saved:Hide();
		if TransmogFrame:IsShown() then
			TransmogUI.UpdateIllusionSlots(TransmogFrame);
		end
	end);
end

function TransmogUI.UpdateIllusionSlot(frame, button)
	local slotId = button:GetID();
	local enabled = TransmogUI.CanHaveIllusion(slotId);
	local enchant, changed = TransmogUI.GetDisplayedIllusion(frame, slotId);
	local illusion = enchant > 0 and TransmogUI.GetIllusion(enchant);

	if illusion then
		button.Icon:SetTexture(illusion.icon);
		button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
		button.Icon:SetWidth(30);
		button.Icon:SetHeight(30);
	else
		button.Icon:SetTexCoord(0, 1, 0, 1);
		button.Icon:SetAtlas("transmog-gearSlot-unassigned-enchant", true);
	end
	button.Icon:SetDesaturated(not enabled);
	button.DisabledIcon:SetShown(not enabled);
	button.Selected:SetShown(frame.illusionSlot == slotId);
	button:SetEnabled(enabled);
	TransmogUI.UpdateSlotPending(button, enabled and changed, enchant);
end

function TransmogUI.UpdateIllusionSlots(frame)
	local preview = frame.CharacterPreview;
	for _, button in ipairs({ preview.MainHandIllusion, preview.OffHandIllusion }) do
		TransmogUI.UpdateIllusionSlot(frame, button);
	end
end

function TransmogFrame_SelectIllusion(frame, slotId)
	if not TransmogUI.CanHaveIllusion(slotId) then
		return;
	end
	frame.illusionSlot = slotId;
	frame.selectedSlot = nil;
	frame.category = TransmogUI.GetItemCategory(TransmogUI.SLOT_BY_ID[slotId], GetInventoryItemLink("player", slotId));
	frame.page = 1;
	if frame.WeaponDropdown then
		frame.WeaponDropdown:Hide();
	end
	frame.SlotTitle:SetText((TRANSMOG_ENCHANT_SLOT or "Иллюзия") .. ": " .. TransmogUI.SLOT_BY_ID[slotId].name);
	TransmogUI.UpdateSlots(frame);
	TransmogUI.RequestIllusions(frame);
end

function TransmogIllusionSlot_OnClick(self, mouseButton)
	local frame = TransmogFrame;
	local slotId = self:GetID();
	if mouseButton == "RightButton" then
		-- убрать иллюзию (или отменить изменение)
		if frame.pendingIllusion[slotId] ~= nil then
			frame.pendingIllusion[slotId] = nil;
		elseif (frame.appliedIllusion[slotId] or 0) > 0 then
			frame.pendingIllusion[slotId] = 0;
		end
		PlaySound("igMainMenuOptionCheckBoxOff");
		TransmogUI.UpdateSlots(frame);
		TransmogUI.UpdatePreview(frame);
		TransmogUI.UpdateGrid(frame);
		return;
	end
	PlaySound("igMainMenuOptionCheckBoxOn");
	TransmogFrame_SelectIllusion(frame, slotId);
end

function TransmogIllusionSlot_OnEnter(self)
	local frame = TransmogFrame;
	local slotId = self:GetID();
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(TRANSMOG_ENCHANT_SLOT or "Иллюзия");
	if TransmogUI.HasOwnEffect(slotId) then
		GameTooltip:AddLine(TRANSMOG_ILLUSION_NO_EFFECT_ITEM, 1, 0.1, 0.1, true);
	elseif not TransmogUI.CanHaveIllusion(slotId) then
		GameTooltip:AddLine(TRANSMOG_ILLUSION_UNAVAILABLE or "Иллюзию можно наложить только на оружие ближнего боя.", 1, 0.1, 0.1, true);
	else
		local enchant = TransmogUI.GetDisplayedIllusion(frame, slotId);
		local illusion = enchant > 0 and TransmogUI.GetIllusion(enchant);
		GameTooltip:AddLine(illusion and illusion.name or NONE, 1, 1, 1);
		GameTooltip:AddLine("ЛКМ - выбрать иллюзию, ПКМ - убрать.", 0.1, 1, 0.1, true);
	end
	GameTooltip:Show();
end

---------------------------------------------------------------------------
-- сетка иллюзий (те же карточки TransmogItemModelTemplate)
---------------------------------------------------------------------------
function TransmogUI.RequestIllusions(frame)
	frame.entries = {};
	if TransmogUI.illusions then
		TransmogUI.UpdateIllusionGrid(frame);
	end
	if Comm_Send then
		frame.waiting, frame.noAnswer, frame.requestElapsed = not TransmogUI.illusions, nil, 0;
		Comm_Send(OP_ILLUSIONS_GET);
	end
	TransmogUI.UpdateGrid(frame);
end

local function FilteredIllusions(frame)
	local list = {};
	local search = strlower(frame.searchText or "");
	for _, illusion in ipairs(TransmogUI.illusions or {}) do
		if (illusion.collected or frame.showUncollected) and (search == "" or strlower(illusion.name):find(search, 1, true)) then
			table.insert(list, illusion);
		end
	end
	return list;
end

function TransmogUI.UpdateIllusionGrid(frame)
	local perPage = TransmogUI.GRID_COLUMNS * TransmogUI.GRID_ROWS;
	local list = FilteredIllusions(frame);
	frame.numPages = math.max(1, math.ceil(#list / perPage));
	frame.page = math.min(frame.page or 1, frame.numPages);
	frame.entries = {};
	local weapon = GetInventoryItemID("player", frame.illusionSlot);
	local first = (frame.page - 1) * perPage;
	for index = 1, perPage do
		local illusion = list[first + index];
		if illusion and weapon then
			table.insert(frame.entries, { itemId = TransmogUI.GetDisplayedItem(frame, frame.illusionSlot) or weapon, illusion = illusion, collected = illusion.collected });
		end
	end
	frame.waiting = TransmogUI.illusions == nil;
end

-- карточка иллюзии: состояние рамки (текущая / наложенная / ожидает)
function TransmogUI.GetIllusionCardAtlas(frame, entry)
	local slotId = frame.illusionSlot;
	local enchant, changed = TransmogUI.GetDisplayedIllusion(frame, slotId);
	if entry.illusion.id == enchant then
		return changed and "transmog-itemcard-transmogrified-pending" or "transmog-itemCard-transmogrified", changed;
	end
	return "transmog-itemCard-default", false;
end

function TransmogUI.OnIllusionCardClick(frame, entry)
	if not entry.collected then
		UIErrorsFrame:AddMessage(TRANSMOGRIFY_STYLE_UNCOLLECTED, 1.0, 0.1, 0.1, 1.0);
		return;
	end
	local slotId = frame.illusionSlot;
	local enchant = entry.illusion.id;
	if enchant == (frame.appliedIllusion[slotId] or 0) then
		frame.pendingIllusion[slotId] = nil;
	else
		frame.pendingIllusion[slotId] = enchant;
	end
	PlaySound("igMainMenuOptionCheckBoxOn");
	TransmogUI.UpdateSlots(frame);
	TransmogUI.UpdatePreview(frame);
	TransmogUI.UpdateGrid(frame);
end

function TransmogUI.OnIllusionCardEnter(model, entry)
	GameTooltip:SetOwner(model, "ANCHOR_RIGHT");
	GameTooltip:SetText(entry.illusion.name, 1, 0.82, 0);
	GameTooltip:AddLine(TRANSMOG_ENCHANT_SLOT or "Иллюзия", 1, 1, 1);
	local spellName = GetSpellInfo(entry.illusion.spell);
	if spellName then
		GameTooltip:AddLine(" ");
		GameTooltip:AddLine((TRANSMOG_SOURCE_LABEL or "Источник: ") .. spellName, 1, 1, 1, true);
	end
	GameTooltip:AddLine(" ");
	if entry.collected then
		GameTooltip:AddLine("Щелчок - наложить иллюзию на оружие.", 0.1, 1, 0.1, true);
	else
		GameTooltip:AddLine("Иллюзия откроется, когда вы изучите эти чары или наденете оружие с ними.", 1, 0.1, 0.1, true);
	end
	GameTooltip:Show();
end

---------------------------------------------------------------------------
-- сервер
---------------------------------------------------------------------------
if Comm_Register then
	Comm_Register(OP_ILLUSIONS, function(cost, text, allowedText)
		TransmogUI.SetIllusionAllowed(allowedText);
		TransmogUI.illusionCost = tonumber(cost) or 0;
		local list = {};
		for enchant, spell, collected in (text or ""):gmatch("(%d+)/(%d+)/(%d)") do
			local name, icon = IllusionName(tonumber(spell));
			table.insert(list, { id = tonumber(enchant), spell = tonumber(spell), collected = collected == "1", name = name, icon = icon });
		end
		-- открытые - впереди, дальше по названию
		table.sort(list, function(a, b)
			if a.collected ~= b.collected then
				return a.collected;
			end
			return a.name < b.name;
		end);
		TransmogUI.illusions = list;

		-- «Коллекции» → «Внешний вид» → «Иллюзии» (Collections\Wardrobe\Blizzard_Wardrobe.lua)
		if WardrobeIllusions_BuildPage then
			WardrobeIllusions_BuildPage();
		end

		local frame = TransmogFrame;
		frame.requestElapsed = nil;
		if frame:IsShown() then
			if frame.illusionSlot then
				TransmogUI.UpdateIllusionGrid(frame);
				TransmogUI.UpdateGrid(frame);
			end
			TransmogUI.UpdateSlots(frame);
		end
	end);
end
