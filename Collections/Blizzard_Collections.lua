-- Окно коллекций (CollectionsJournal). Имена функций и индексы вкладок - как в ретейле.

-- атлас с проверкой (если атласа нет - текстура остаётся пустой, а не зелёной)
function CollectionsUtil_SetAtlas(texture, atlas)
	if texture and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas);
	elseif texture then
		texture:SetTexture(nil);
	end
end

-- строки ретейла, которых нет в GlobalStrings (нужны до загрузки XML: KeyValue type="global")
MOUNT_JOURNAL_SUMMON_RANDOM_FAVORITE_MOUNT = MOUNT_JOURNAL_SUMMON_RANDOM_FAVORITE_MOUNT or "Случайное избранное средство передвижения";
PET_JOURNAL_SUMMON_RANDOM_FAVORITE_PET = PET_JOURNAL_SUMMON_RANDOM_FAVORITE_PET or "Призвать случайного избранного питомца";

-- CollectionsBackgroundTemplate
local BACKGROUND_TILE_FILE = "Interface\\Collections\\CollectionsBackgroundTile";
local BACKGROUND_TILE_SIZE = 256;

local function SetAtlasFlipped(texture, atlas, flipX, flipY)
	local info = C_Texture.GetAtlasInfo(atlas);
	if not info then
		return;
	end
	texture:SetTexture(info.file);
	local left, right, top, bottom = info.left, info.right, info.top, info.bottom;
	if flipX then left, right = right, left; end
	if flipY then top, bottom = bottom, top; end
	texture:SetTexCoord(left, right, top, bottom);
end

function CollectionsBackground_OnLoad(self)
	self.BackgroundTile:SetTexture(BACKGROUND_TILE_FILE);
	CollectionsUtil_SetAtlas(self.ShadowCenter, "collections-background-shadow-large");
	SetAtlasFlipped(self.BGCornerTopLeft, "collections-background-corner", false, false);
	SetAtlasFlipped(self.BGCornerTopRight, "collections-background-corner", true, false);
	SetAtlasFlipped(self.BGCornerBottomLeft, "collections-background-corner", false, true);
	SetAtlasFlipped(self.BGCornerBottomRight, "collections-background-corner", true, true);
	CollectionsBackground_UpdateTiling(self);
end

-- tile the parchment instead of stretching it (texcoords above 1 repeat the texture)
function CollectionsBackground_UpdateTiling(self)
	local width, height = self:GetWidth(), self:GetHeight();
	if width and width > 0 and height and height > 0 then
		self.BackgroundTile:SetTexCoord(0, width / BACKGROUND_TILE_SIZE, 0, height / BACKGROUND_TILE_SIZE);
	end
end

COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS = 1;
COLLECTIONS_JOURNAL_TAB_INDEX_PETS = 2;
COLLECTIONS_JOURNAL_TAB_INDEX_TOYS = 3;
COLLECTIONS_JOURNAL_TAB_INDEX_HEIRLOOMS = 4;
COLLECTIONS_JOURNAL_TAB_INDEX_APPEARANCES = 5;

-- позицию окна задаёт UIParent (панель слева, отступ 15)
UIPanelWindows["CollectionsJournal"] = { area = "left", pushable = 0, width = 703, whileDead = 1, xOffset = "15", yOffset = "0" };

function CollectionsJournal_OnLoad(self)
	TabSystemOwnerMixin.OnLoad(self);
	self:SetTabSystem(self.TabSystem);
	self.tabIDs = {};      -- COLLECTIONS_JOURNAL_TAB_INDEX_* -> tabID системы вкладок
	self.tabInfo = {};

	if ButtonFrameTemplate_HideButtonBar then
		ButtonFrameTemplate_HideButtonBar(self);
	end
	if self.Inset then
		self.Inset:Hide();   -- у каждой вкладки свои вставки
	end

	-- уровни как у PlayerSpellsFrame: портрет (+19) под ободком рамки (+20),
	-- заголовок (+21) и крестик (+22) сверху, вкладки-панели (+2) под рамкой, TabSystem (+25)
	if self.SetFrameLevelsFromBaseLevel then
		self:SetFrameLevelsFromBaseLevel(self:GetFrameLevel());
	end
	self.TabSystem:SetFrameLevel(self:GetFrameLevel() + 25);
end

-- регистрация вкладки: вызывается один раз для каждой панели (Blizzard_CollectionsInit.lua)
function CollectionsJournal_RegisterTab(tabIndex, panel, title, portrait)
	local journal = CollectionsJournal;
	panel:SetFrameLevel(journal:GetFrameLevel() + 2);   -- под рамкой и крестиком, как в PlayerSpellsFrame
	local tabID = journal:AddNamedTab(title, panel);
	journal.tabIDs[tabIndex] = tabID;
	journal:SetTabCallback(tabID, function()
		journal.selectedTabIndex = tabIndex;
		if journal.SetTitle then
			journal:SetTitle(title);
		end
		if journal.SetPortraitToAsset then
			journal:SetPortraitToAsset(portrait);
		end
	end);
end

function CollectionsJournal_GetTab(self)
	return CollectionsJournal.selectedTabIndex or COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS;
end

function CollectionsJournal_SetTab(self, tabIndex)
	local tabID = CollectionsJournal.tabIDs[tabIndex];
	if tabID then
		CollectionsJournal:SetTab(tabID);
	end
end

function CollectionsJournal_UpdateSelectedTab(self)
	CollectionsJournal_SetTab(self, CollectionsJournal_GetTab(self));
end

function CollectionsJournal_OnShow(self)
	PlaySound("igCharacterInfoOpen");
	CollectionsJournal_UpdateSelectedTab(self);
	if UpdateMicroButtons then
		UpdateMicroButtons();
	end
end

function CollectionsJournal_OnHide(self)
	PlaySound("igCharacterInfoClose");
	if UpdateMicroButtons then
		UpdateMicroButtons();
	end
end

function CollectionsJournal_LoadUI()
	return true;   -- в ретейле аддон грузится по требованию, здесь он всегда загружен
end

function SetCollectionsJournalShown(shown, tabIndex)
	if shown then
		ShowUIPanel(CollectionsJournal);
		if tabIndex then
			CollectionsJournal_SetTab(CollectionsJournal, tabIndex);
		end
	else
		HideUIPanel(CollectionsJournal);
	end
end

function ToggleCollectionsJournal(tabIndex)
	local tabMatches = not tabIndex or tabIndex == CollectionsJournal_GetTab(CollectionsJournal);
	local isShown = CollectionsJournal:IsShown() and tabMatches;
	SetCollectionsJournalShown(not isShown, tabIndex);
end

SLASH_COLLECTIONS1 = "/collections";
SLASH_COLLECTIONS2 = "/mounts";
SlashCmdList.COLLECTIONS = function()
	ToggleCollectionsJournal(COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS);
end

SLASH_PETJOURNAL1 = "/pets";
SlashCmdList.PETJOURNAL = function()
	ToggleCollectionsJournal(COLLECTIONS_JOURNAL_TAB_INDEX_PETS);
end
