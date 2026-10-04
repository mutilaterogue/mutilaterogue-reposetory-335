SECONDS_PER_PULSE = 1;

function GlueButtonMaster_OnUpdate(self, elapsed)
	if ( _G[self:GetName().."Glow"]:IsShown() ) then
		local sign = self.pulseSign;
		local counter;
		
		if ( not self.pulsing ) then
			counter = 0;
			self.pulsing = 1;
			sign = 1;
		else
			counter = self.pulseCounter + (sign * elapsed);
			if ( counter > SECONDS_PER_PULSE ) then
				counter = SECONDS_PER_PULSE;
				sign = -sign;
			elseif ( counter < 0) then
				counter = 0;
				sign = -sign;
			end
		end
		
		local alpha = counter / SECONDS_PER_PULSE;
		_G[self:GetName().."Glow"]:SetVertexColor(1.0, 1.0, 1.0, alpha);

		self.pulseSign = sign;
		self.pulseCounter = counter;
	end
end

-- retail red three slice buttons (GlueButtons.xml): the atlases by state, the ends scaled to the button height
local function AtlasInfo(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name);
end

local function SetPart(texture, atlas, fallback)
	if AtlasInfo(atlas) then
		texture:SetAtlas(atlas);
	elseif fallback and AtlasInfo(fallback) then
		texture:SetAtlas(fallback);
	end
end

function GlueRetailButton_Update(self, pressed)
	if not self.Left then
		return;
	end
	local kit = self.atlasName or "128-RedButton";
	local state = "";
	if not self:IsEnabled() then
		state = "-Disabled";
	elseif pressed then
		state = "-Pressed";
	end
	SetPart(self.Left, kit .. "-Left" .. state, kit .. "-Left");
	SetPart(self.Right, kit .. "-Right" .. state, kit .. "-Right");
	SetPart(self.Center, "_" .. kit .. "-Center" .. (state ~= "" and state or ""), "_" .. kit .. "-Center");
	if state ~= "" and not AtlasInfo("_" .. kit .. "-Center" .. state) and AtlasInfo("_" .. kit .. state) then
		self.Center:SetAtlas("_" .. kit .. state);
	end
	SetPart(self.Glow, kit .. "-Highlight");

	-- the ends keep their proportions at the button height, the center fills the rest
	local height = self:GetHeight();
	local left, right = AtlasInfo(kit .. "-Left"), AtlasInfo(kit .. "-Right");
	if height and height > 0 and left and right and (left.height or 0) > 0 and (right.height or 0) > 0 then
		local leftWidth = left.width * height / left.height;
		local rightWidth = right.width * height / right.height;
		local total = self:GetWidth() or 0;
		if total > 0 and leftWidth + rightWidth > total then
			local scale = total / (leftWidth + rightWidth);
			leftWidth, rightWidth = leftWidth * scale, rightWidth * scale;
		end
		self.Left:SetWidth(leftWidth);
		self.Right:SetWidth(rightWidth);
	end
	self.Center:ClearAllPoints();
	self.Center:SetPoint("TOPLEFT", self.Left, "TOPRIGHT");
	self.Center:SetPoint("BOTTOMRIGHT", self.Right, "BOTTOMLEFT");
end
