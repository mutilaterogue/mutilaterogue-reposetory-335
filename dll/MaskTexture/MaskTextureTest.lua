-- MaskTexture test page (optional, not needed in game): /masktest shows the cases in a row, again hides them.
--   1 circle   2 desaturated   3 texcoords rotated 45°   4 two masks   5 cropped texcoords   6 <MaskTexture> in XML
local ICON = "Interface\\Icons\\INV_Misc_QuestionMark";
-- the retail portrait mask (TempPortraitAlphaMask may be replaced by an opaque one for square portraits)
local MASK_ATLAS = "UI-HUD-UnitFrame-Player-Portrait-Mask";
local SIZE, GAP = 64, 24;

local function Cell(parent, index, label)
	local icon = parent:CreateTexture(nil, "ARTWORK");
	icon:SetSize(SIZE, SIZE);
	icon:SetPoint("LEFT", (index - 1) * (SIZE + GAP), 0);
	icon:SetTexture(ICON);
	local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	text:SetPoint("TOP", icon, "BOTTOM", 0, -4);
	text:SetText(label);
	return icon;
end

local function Mask(parent, icon, xOffset)
	local mask = parent:CreateMaskTexture();
	mask:SetAtlas(MASK_ATLAS);
	mask:SetPoint("TOPLEFT", icon, "TOPLEFT", xOffset or 0, 0);
	mask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", xOffset or 0, 0);
	icon:AddMaskTexture(mask);
	return mask;
end

local function Build()
	local f = CreateFrame("Frame", "MaskTextureTestFrame", UIParent);
	f:SetSize(6 * SIZE + 5 * GAP, SIZE);
	f:SetPoint("CENTER", 0, 120);

	Mask(f, Cell(f, 1, "circle"));

	local desaturated = Cell(f, 2, "desaturated");
	desaturated:SetDesaturated(true);
	Mask(f, desaturated);

	-- 45° rotation through the 8 texcoords (UL, LL, UR, LR), scaled in to stay inside the icon
	local rotated = Cell(f, 3, "rotated 45");
	local c, s = 0.5 * math.cos(math.rad(45)) * 0.7, 0.5 * math.sin(math.rad(45)) * 0.7;
	local function corner(x, y) return 0.5 + x * c - y * s, 0.5 + x * s + y * c; end
	local ulx, uly = corner(-1, -1);
	local llx, lly = corner(-1, 1);
	local urx, ury = corner(1, -1);
	local lrx, lry = corner(1, 1);
	rotated:SetTexCoord(ulx, uly, llx, lly, urx, ury, lrx, lry);
	Mask(f, rotated);

	-- two circles shifted apart: only their overlap (a lens) stays
	local lens = Cell(f, 4, "two masks");
	Mask(f, lens, -16);
	Mask(f, lens, 16);

	local cropped = Cell(f, 5, "cropped");
	cropped:SetTexCoord(0.08, 0.92, 0.08, 0.92);
	Mask(f, cropped);

	local xml = MaskTextureXMLTest;
	if xml then
		xml:SetParent(f);
		xml:ClearAllPoints();
		xml:SetPoint("LEFT", 5 * (SIZE + GAP), 0);
		xml:Show();
		local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
		text:SetPoint("TOP", xml, "BOTTOM", 0, -4);
		text:SetText("XML: " .. xml.Icon:GetNumMaskTextures() .. " mask");
	end
	return f;
end

local helper = CreateFrame("Frame");
helper:RegisterEvent("PLAYER_LOGIN");
helper:SetScript("OnEvent", function()
	SLASH_MASKTEST1 = "/masktest";
	SlashCmdList["MASKTEST"] = function()
		if not TextureAddMask then
			print("MaskTexture: the DLL functions are not registered");
			return;
		end
		local f = MaskTextureTestFrame or Build();
		if MaskTextureTestFrame and f:IsShown() then
			f:Hide();
		else
			f:Show();
		end
	end;
end);
