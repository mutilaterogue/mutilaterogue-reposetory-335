-- Вкладки, которые ещё не сделаны: Игрушки, Наследуемые, Внешний вид.
-- Каждая - своя панель с тем же именем, что в ретейле (ToyBox, HeirloomsJournal,
-- WardrobeCollectionFrame), чтобы потом заменить заглушку настоящей вкладкой.

local function CreateComingSoonPanel(frameName, tabIndex, watermarkAtlas, description)
	local panel = CreateFrame("Frame", frameName, CollectionsJournal);
	panel:SetPoint("TOPLEFT", CollectionsJournal, "TOPLEFT", 0, -60);
	panel:SetPoint("BOTTOMRIGHT", CollectionsJournal, "BOTTOMRIGHT", 0, 0);
	panel:Hide();

	local inset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate");
	inset:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, 0);
	inset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 26);

	local background = inset:CreateTexture(nil, "BACKGROUND", nil, 1);
	background:SetPoint("TOPLEFT", inset, "TOPLEFT", 3, -3);
	background:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -3, 3);
	if C_Texture.GetAtlasInfo("collections-background-tile") then
		background:SetAtlas("collections-background-tile");
	else
		background:SetTexture(0.05, 0.05, 0.05, 1);
	end

	if watermarkAtlas and C_Texture.GetAtlasInfo(watermarkAtlas) then
		local watermark = inset:CreateTexture(nil, "ARTWORK");
		watermark:SetAtlas(watermarkAtlas, true);
		watermark:SetPoint("CENTER", inset, "CENTER", 0, 30);
		watermark:SetAlpha(0.6);
	end

	local title = inset:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge");
	title:SetPoint("CENTER", inset, "CENTER", 0, -40);
	title:SetText("В скором времени");

	local text = inset:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
	text:SetPoint("TOP", title, "BOTTOM", 0, -12);
	text:SetWidth(420);
	text:SetText(description);

	CollectionsJournal_RegisterTab(tabIndex, panel);
	return panel;
end

CreateComingSoonPanel("ToyBox", COLLECTIONS_JOURNAL_TAB_INDEX_TOYS, "collections-watermark-toy",
	"Коллекция игрушек появится в одном из следующих обновлений.");
CreateComingSoonPanel("HeirloomsJournal", COLLECTIONS_JOURNAL_TAB_INDEX_HEIRLOOMS, "collections-watermark-heirloom",
	"Коллекция наследуемых предметов появится в одном из следующих обновлений.");
CreateComingSoonPanel("WardrobeCollectionFrame", COLLECTIONS_JOURNAL_TAB_INDEX_APPEARANCES, nil,
	"Коллекция обликов и комплектов появится в одном из следующих обновлений.");
