local ItemQuality = {
	Poor = 0,
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Artifact = 6,
}

local QUALITY_EDGE_SIZE = 1;

function CreateQualityEdge(button)
	local edge = CreateFrame("Frame", nil, button);
	edge:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0);
	edge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0);
	edge:SetFrameLevel(button:GetFrameLevel() + 2);
	edge:SetBackdrop({
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = QUALITY_EDGE_SIZE,
	});
	edge:EnableMouse(false);
	edge:Hide();
	return edge;
end

function SetItemButtonQuality(button, quality)
	if ( not button ) then
		return;
	end

	local border = button.IconBorder;
	if ( not border ) then
		local name = button:GetName();
		border = name and _G[name.."IconBorder"];
		if ( not border ) then
			border = button:CreateTexture(name and name.."IconBorder" or nil, "OVERLAY");
			border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays");
			border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625);
			border:SetPoint("CENTER", button, "CENTER", 0, 0);
			border:SetWidth(button:GetWidth() + 3);
			border:SetHeight(button:GetHeight() + 3);
			border:Hide();
		end
		button.IconBorder = border;
	end

	if ( quality and quality >= ItemQuality.Uncommon ) then
		local r, g, b = GetItemQualityColor(quality);
		border:SetVertexColor(r, g, b);
		border:Show();
	else
		border:Hide();
	end
end

function SetItemButtonCount(button, count)
	if ( not button ) then
		return;
	end

	if ( not count ) then
		count = 0;
	end

	button.count = count;
	local countString = button.Count or _G[button:GetName().."Count"];
	if ( count > 1 or (button.isBag and count > 0) ) then
		if ( count > (button.maxDisplayCount or 9999) ) then
			count = "*";
		end
		countString:SetText(count);
		countString:Show();
	else
		countString:Hide();
	end
end

function SetItemButtonStock(button, numInStock)
	if ( not button ) then
		return;
	end

	if ( not numInStock ) then
		numInStock = "";
	end

	button.numInStock = numInStock;
	if ( numInStock > 0 ) then
		_G[button:GetName().."Stock"]:SetFormattedText(MERCHANT_STOCK, numInStock);
		_G[button:GetName().."Stock"]:Show();
	else
		_G[button:GetName().."Stock"]:Hide();
	end
end

function SetItemButtonTexture(button, texture)
	if ( not button ) then
		return;
	end

	local icon = button.Icon or button.icon or _G[button:GetName().."IconTexture"];
	if ( texture ) then
		icon:Show();
	else
		icon:Hide();
	end

	if button:GetAttribute("useCircularIconBorder") then
		SetPortraitToTexture(icon, texture);
	else
		SetPortraitToTexture(icon, "");
		icon:SetTexture(texture);
	end
end

function SetItemButtonTextureVertexColor(button, r, g, b)
	if ( not button ) then
		return;
	end

	local icon = button.Icon or button.icon or _G[button:GetName().."IconTexture"];
	icon:SetVertexColor(r, g, b);
end

function SetItemButtonDesaturated(button, desaturated, r, g, b)
	if ( not button ) then
		return;
	end
	local icon = button.Icon or button.icon or _G[button:GetName().."IconTexture"];
	if ( not icon ) then
		return;
	end
	local shaderSupported = icon:SetDesaturated(desaturated);

	if ( not desaturated ) then
		r = 1.0;
		g = 1.0;
		b = 1.0;
	elseif ( not r or not shaderSupported ) then
		r = 0.5;
		g = 0.5;
		b = 0.5;
	end
	
	icon:SetVertexColor(r, g, b);
end

function SetItemButtonNormalTextureVertexColor(button, r, g, b)
	if ( not button ) then
		return;
	end
	
	_G[button:GetName().."NormalTexture"]:SetVertexColor(r, g, b);
end

function SetItemButtonNameFrameVertexColor(button, r, g, b)
	if ( not button ) then
		return;
	end

	local nameFrame = button.NameFrame or _G[button:GetName().."NameFrame"];
	nameFrame:SetVertexColor(r, g, b);
end

function SetItemButtonSlotVertexColor(button, r, g, b)
	if ( not button ) then
		return;
	end
	
	_G[button:GetName().."SlotTexture"]:SetVertexColor(r, g, b);
end

function HandleModifiedItemClick(link)
	if ( IsModifiedClick("CHATLINK") ) then
		if ( ChatEdit_InsertLink(link) ) then
			return true;
		end
	end
	if ( IsModifiedClick("DRESSUP") ) then
		DressUpItemLink(link);
		return true;
	end
	return false;
end
