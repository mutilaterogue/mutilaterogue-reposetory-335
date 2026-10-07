-- if you change something here you probably want to change the glue version too

local OPTIONS_FARCLIP_MIN = 177;
local OPTIONS_FARCLIP_MAX = 3000;

local VIDEO_OPTIONS_CUSTOM_QUALITY = 6;

local VIDEO_OPTIONS_COMPARISON_EPSILON = 0.000001;


-- [[ Generic Video Options Panel ]] --

function VideoOptionsPanel_Okay (self)
	for _, control in next, self.controls do
		if ( control.newValue ) then
			if ( control.value ~= control.newValue ) then
				if ( control.gameRestart ) then
					VideoOptionsFrame.gameRestart = true;
				end
				if ( control.logout ) then
					VideoOptionsFrame.logout = true;
				end
				if ( control.restart ) then
					VideoOptionsFrame.gxRestart = true;
				end
				control:SetValue(control.newValue);
				control.value = control.newValue;
				control.newValue = nil;
			end
		elseif ( control.value ) then
			control:SetValue(control.value);
		end
	end
end

function VideoOptionsPanel_Cancel (self)
	for _, control in next, self.controls do
		if ( control.newValue ) then
			if ( control.value and control.value ~= control.newValue ) then
				if ( control.restart ) then
					VideoOptionsFrame.gxRestart = true;
				end
				-- we need to force-set the value here just in case the control was doing dynamic updating
				control:SetValue(control.value);
				control.newValue = nil;
			end
		elseif ( control.value ) then
			control:SetValue(control.value);
		end
	end
end

function VideoOptionsPanel_Default (self)
	for _, control in next, self.controls do
		if ( control.defaultValue and control.value ~= control.defaultValue ) then
			if ( control.restart ) then
				VideoOptionsFrame.gxRestart = true;
			end
			control:SetValue(control.defaultValue);
			control.newValue = nil;
		end
	end
end

function VideoOptionsPanel_OnLoad (self, okay, cancel, default, refresh)
	okay = okay or VideoOptionsPanel_Okay;
	cancel = cancel or VideoOptionsPanel_Cancel;
	default = default or VideoOptionsPanel_Default;
	refresh = refresh or BlizzardOptionsPanel_Refresh;
	BlizzardOptionsPanel_OnLoad(self, okay, cancel, default, refresh);

	OptionsFrame_AddCategory(VideoOptionsFrame, self);
end

-- [[ Resolution Panel ]] --

ResolutionPanelOptions = {
	useUiScale = { text = "USE_UISCALE" },
	gxVSync = { text = "VERTICAL_SYNC" },
	gxTripleBuffer = { text = "TRIPLE_BUFFER" },
	gxCursor = { text = "HARDWARE_CURSOR" },
	gxFixLag = { text = "FIX_LAG" },
	gxWindow = { text = "WINDOWED_MODE" },
	gxMaximize = { text = "WINDOWED_MAXIMIZED" },
	windowResizeLock = { text = "WINDOW_LOCK" },
	desktopGamma = { text = "DESKTOP_GAMMA" },
	gamma = { text = "GAMMA", minValue = -.5, maxValue = .5, valueStep = .1 },
	uiscale = { text = "", minValue = .64, maxValue = 1, valueStep = .01 },
}

function VideoOptionsResolutionPanel_Default (self)
	RestoreVideoResolutionDefaults();
	for _, control in next, self.controls do
		if ( control == VideoOptionsResolutionPanelUseUIScale or control == VideoOptionsResolutionPanelUIScaleSlider ) then
			control:SetValue(control.defaultValue);
		end
		control.newValue = nil;
	end
end

function VideoOptionsResolutionPanel_Refresh (self)
	BlizzardOptionsPanel_Refresh(self);
	VideoOptionsResolutionPanel_RefreshGammaControls();
end

function VideoOptionsResolutionPanel_OnLoad (self)
	self.name = RESOLUTION_LABEL;
	self.options = ResolutionPanelOptions;
	VideoOptionsPanel_OnLoad(self, nil, nil, VideoOptionsResolutionPanel_Default, VideoOptionsResolutionPanel_Refresh);

	self:SetScript("OnEvent", VideoOptionsResolutionPanel_OnEvent);
end

function VideoOptionsResolutionPanel_OnEvent (self, event, ...)
	BlizzardOptionsPanel_OnEvent(self, event, ...);

	if ( event == "PLAYER_ENTERING_WORLD" ) then
		-- don't allow systems that don't support features to enable them
		local anisotropic, pixelShaders, vertexShaders, trilinear, buffering, maxAnisotropy, hardwareCursor = GetVideoCaps();
		if ( not hardwareCursor ) then
			VideoOptionsResolutionPanelHardwareCursor:SetChecked(false);
			VideoOptionsResolutionPanelHardwareCursor:Disable();
		end
		VideoOptionsResolutionPanelHardwareCursor.SetChecked =
			function (self, checked)
				local anisotropic, pixelShaders, vertexShaders, trilinear, buffering, maxAnisotropy, hardwareCursor = GetVideoCaps();
				if ( not hardwareCursor ) then
					checked = false;
				end
				getmetatable(self).__index.SetChecked(self, checked);
			end
		VideoOptionsResolutionPanelHardwareCursor.Enable =
			function (self)
				local anisotropic, pixelShaders, vertexShaders, trilinear, buffering, maxAnisotropy, hardwareCursor = GetVideoCaps();
				if ( not hardwareCursor ) then
					return;
				end
				getmetatable(self).__index.Enable(self);
				local text = _G[self:GetName().."Text"];
				local fontObject = text:GetFontObject();
				_G[self:GetName().."Text"]:SetTextColor(fontObject:GetTextColor());
			end
	end
end

function VideoOptionsResolutionPanel_RefreshGammaControls ()
	if ( VideoOptionsResolutionPanelWindowed:GetChecked() ) then
		VideoOptionsResolutionPanelDesktopGamma:SetChecked();
		VideoOptionsResolutionPanelDesktopGamma:Disable();
		BlizzardOptionsPanel_Slider_Disable(VideoOptionsResolutionPanelGammaSlider);
	else
		VideoOptionsResolutionPanelDesktopGamma:Enable();
		if ( VideoOptionsResolutionPanelDesktopGamma:GetChecked() ) then
			BlizzardOptionsPanel_Slider_Disable(VideoOptionsResolutionPanelGammaSlider);
		else
			BlizzardOptionsPanel_Slider_Enable(VideoOptionsResolutionPanelGammaSlider);
		end
	end
end

function VideoOptionsResolutionPanel_SetWindowed ()
	VideoOptionsResolutionPanel_RefreshGammaControls();
	local value;
	if ( VideoOptionsResolutionPanelWindowed:GetChecked() or
		 VideoOptionsResolutionPanelDesktopGamma:GetChecked() ) then
		value = 1;
	else
		value = 0;
	end
	BlizzardOptionsPanel_SetCVarSafe("desktopGamma", value);
end

function VideoOptionsResolutionPanel_SetGamma (value)
	VideoOptionsResolutionPanel_RefreshGammaControls();
	BlizzardOptionsPanel_SetCVarSafe("desktopGamma", value);
end

function VideoOptionsResolutionPanelResolutionDropDown_OnLoad(self)
	local value = GetCurrentResolution();

	self.value = value;
	self.defaultValue = 2;
	self.restart = true;

	UIDropDownMenu_SetWidth(self, 110);
	UIDropDownMenu_Initialize(self, VideoOptionsResolutionPanelResolutionDropDown_Initialize);
	UIDropDownMenu_SetSelectedID(self, value, 1);

	self.SetValue = 
		function (self, value) 
			SetScreenResolution(value);
		end;
	self.GetValue =
		function (self)
			return GetCurrentResolution();
		end
	self.RefreshValue = 
		function (self)
			local value = GetCurrentResolution();
			UIDropDownMenu_Initialize(self, VideoOptionsResolutionPanelResolutionDropDown_Initialize);
			UIDropDownMenu_SetSelectedID(self, value, 1);
			self.value = value;
			self.newValue = value;
		end
end

function VideoOptionsResolutionPanelResolutionDropDown_Initialize()
	VideoOptionsResolutionPanelResolutionDropDown_LoadResolutions(GetScreenResolutions());	
end

function VideoOptionsResolutionPanelResolutionDropDown_LoadResolutions(...)
	local info = UIDropDownMenu_CreateInfo();
	local resolution, xIndex, width, height;
	for i=1, select("#", ...) do
		resolution = (select(i, ...));
		xIndex = strfind(resolution, "x");
		width = strsub(resolution, 1, xIndex-1);
		height = strsub(resolution, xIndex+1, strlen(resolution));
		if ( width/height > 4/3 ) then
			resolution = resolution.." "..WIDESCREEN_TAG;
		end
		info.text = resolution;
		info.value = resolution;
		info.func = VideoOptionsResolutionPanelResolutionDropDown_OnClick;
		info.checked = nil;
		UIDropDownMenu_AddButton(info);
	end
end

function VideoOptionsResolutionPanelResolutionDropDown_OnClick(self)
	local value = self:GetID();
	local dropdown = VideoOptionsResolutionPanelResolutionDropDown;
	UIDropDownMenu_SetSelectedID(dropdown, value, 1);
	if ( dropdown.value == value ) then
		dropdown.newValue = nil;
	else
		dropdown.newValue = value;
	end
	VideoOptionsFrameApply:Enable();
end

function VideoOptionsResolutionPanelRefreshDropDown_OnLoad(self)
	self.cvar = "gxRefresh";

	local value = BlizzardOptionsPanel_GetCVarSafe(self.cvar);

	self.defaultValue = BlizzardOptionsPanel_GetCVarDefaultSafe(self.cvar);
	self.value = value;
	self.restart = true;

	UIDropDownMenu_SetWidth(self, 110);
	UIDropDownMenu_Initialize(self, VideoOptionsResolutionPanelRefreshDropDown_Initialize);
	UIDropDownMenu_SetSelectedValue(self, value);

	self.SetValue =
		function (self, value) 
			BlizzardOptionsPanel_SetCVarSafe(self.cvar, value);
		end;
	self.GetValue =
		function (self)
			return BlizzardOptionsPanel_GetCVarSafe(self.cvar);
		end
	self.RefreshValue = 
		function (self)
			local value = BlizzardOptionsPanel_GetCVarSafe(self.cvar);
			UIDropDownMenu_Initialize(self, VideoOptionsResolutionPanelRefreshDropDown_Initialize);
			UIDropDownMenu_SetSelectedValue(self, value);
			self.value = value;
			self.newValue = value;
		end
end

function VideoOptionsResolutionPanelRefreshDropDown_Initialize()
	VideoOptionsResolutionPanel_GetRefreshRates(GetRefreshRates());
end

function VideoOptionsResolutionPanel_GetRefreshRates(...)
	local info = UIDropDownMenu_CreateInfo();
	local checked;
	if ( select("#", ...) == 1 and select(1, ...) == 0 ) then
		VideoOptionsResolutionPanelRefreshDropDownButton:Disable();
		VideoOptionsResolutionPanelRefreshDropDownLabel:SetVertexColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b);
		VideoOptionsResolutionPanelRefreshDropDownText:SetVertexColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b);
		return;
	end
	for i=1, select("#", ...) do
		info.text = select(i, ...)..HERTZ;
		info.func = VideoOptionsResolutionPanelRefreshDropDown_OnClick;

		if ( UIDropDownMenu_GetSelectedValue(VideoOptionsResolutionPanelRefreshDropDown) and tonumber(UIDropDownMenu_GetSelectedValue(VideoOptionsResolutionPanelRefreshDropDown)) == select(i, ...) ) then
			checked = 1;
			UIDropDownMenu_SetText(VideoOptionsResolutionPanelRefreshDropDown, info.text);
		else
			checked = nil;
		end
		info.value = select(i, ...)
		info.checked = checked;
		UIDropDownMenu_AddButton(info);
	end
end

function VideoOptionsResolutionPanelRefreshDropDown_OnClick(self)
	local value = self.value;
	local dropdown = VideoOptionsResolutionPanelRefreshDropDown;
	UIDropDownMenu_SetSelectedValue(dropdown, value);
	if ( dropdown.value == value ) then
		dropdown.newValue = nil;
	else
		dropdown.newValue = value;
	end
	VideoOptionsFrameApply:Enable();
end

function VideoOptionsResolutionPanelMultiSampleDropDown_OnLoad(self)
	local value = GetCurrentMultisampleFormat();

	self.defaultValue = 1;
	self.value = value;
	self.restart = true;

	UIDropDownMenu_SetWidth(self, 160);
	UIDropDownMenu_SetAnchor(self, 0, 23, "TOPRIGHT", "VideoOptionsResolutionPanelMultiSampleDropDownRight", "BOTTOMRIGHT");
	UIDropDownMenu_Initialize(self, VideoOptionsResolutionPanelMultiSampleDropDown_Initialize);
	UIDropDownMenu_SetSelectedID(self, value);

	self.SetValue = 
		function (self, value)
			SetMultisampleFormat(value);
		end;
	self.GetValue =
		function (self)
			return GetCurrentMultisampleFormat();
		end
	self.RefreshValue = 
		function (self)
			local value = GetCurrentMultisampleFormat();
			UIDropDownMenu_Initialize(self, VideoOptionsResolutionPanelMultiSampleDropDown_Initialize);
			UIDropDownMenu_SetSelectedID(self, value);
			self.value = value;
			self.newValue = value;
		end
end

function VideoOptionsResolutionPanelMultiSampleDropDown_Initialize()
	VideoOptionsResolutionPanel_GetMultisampleFormats(GetMultisampleFormats());
end

function VideoOptionsResolutionPanel_GetMultisampleFormats(...)
	local colorBits, depthBits, multiSample;
	local info = UIDropDownMenu_CreateInfo();
	local index = 1;
	for i=1, select("#", ...), 3 do
		colorBits, depthBits, multiSample = select(i, ...);
		info.text = format(MULTISAMPLING_FORMAT_STRING, colorBits, depthBits, multiSample);
		info.func = VideoOptionsResolutionPanelMultiSampleDropDown_OnClick;
		
		if ( index == UIDropDownMenu_GetSelectedID(VideoOptionsResolutionPanelMultiSampleDropDown) ) then
			info.checked = 1;
			UIDropDownMenu_SetText(VideoOptionsResolutionPanelMultiSampleDropDown, info.text);
		else
			info.checked = nil;
		end
		UIDropDownMenu_AddButton(info);
		index = index + 1;
	end
end

function VideoOptionsResolutionPanelMultiSampleDropDown_OnClick(self)
	local value = self:GetID();
	local dropdown = VideoOptionsResolutionPanelMultiSampleDropDown;
	UIDropDownMenu_SetSelectedID(dropdown, value);
	if ( dropdown.value == value ) then
		dropdown.newValue = nil;
	else
		dropdown.newValue = value;
	end
	VideoOptionsFrameApply:Enable();
end


-- [[ Effects Panel ]] --

EffectsPanelOptions = {
	farclip = { text = "FARCLIP", minValue = OPTIONS_FARCLIP_MIN, maxValue = OPTIONS_FARCLIP_MAX, valueStep = (OPTIONS_FARCLIP_MAX - OPTIONS_FARCLIP_MIN)/10},
	TerrainMip = { text = "TERRAIN_MIP", minValue = 0, maxValue = 1, valueStep = 1, logout = 1, tooltip = OPTION_TOOLTIP_TERRAIN_TEXTURE, tooltipRequirement = OPTION_LOGOUT_REQUIREMENT,},
	particleDensity = { text = "PARTICLE_DENSITY", minValue = 0.1, maxValue = 1.0, valueStep = 0.1},
	environmentDetail = { text = "ENVIRONMENT_DETAIL", minValue = 0.5, maxValue = 5, valueStep = .25},
	groundEffectDensity = { text = "GROUND_DENSITY", minValue = 16, maxValue = 64, valueStep = 8},
	groundEffectDist = { text = "GROUND_RADIUS", minValue = 70, maxValue = 500, valueStep = 10 },
	BaseMip = { text = "TEXTURE_DETAIL", minValue = 0, maxValue = 1, valueStep = 1, tooltipOwnerPoint = "TOPLEFT", },
	extShadowQuality = { text = "SHADOW_QUALITY", minValue = 0, maxValue = 4, valueStep = 1 },
	textureFilteringMode = { text = "ANISOTROPIC", minValue = 0, maxValue = 5, valueStep = 1, gameRestart = 1, tooltipOwnerPoint = "TOPLEFT", tooltipRequirement = OPTION_RESTART_REQUIREMENT, },
	weatherDensity = { text = "WEATHER_DETAIL", minValue = 0, maxValue = 3, valueStep = 1, tooltipOwnerPoint = "TOPLEFT", },
	componentTextureLevel = { text = "PLAYER_DETAIL", minValue = 8, maxValue = 9, valueStep = 1, tooltipPoint = "BOTTOMRIGHT", tooltipOwnerPoint = "TOPLEFT", gameRestart = 1, tooltipRequirement = OPTION_RESTART_REQUIREMENT, },
	specular = { text = "TERRAIN_HIGHLIGHTS", logout = 1, tooltipRequirement = OPTION_LOGOUT_REQUIREMENT, },
	ffxGlow = { text = "FULL_SCREEN_GLOW", },
	ffxDeath = { text = "DEATH_EFFECT", },
	projectedTextures = { text = "PROJECTED_TEXTURES", },
	quality = { text = "", minValue = 1, maxValue = 6, valueStep = 1 },
}

function VideoOptionsEffectsPanel_Default (self)
	RestoreVideoEffectsDefaults();
	for _, control in next, self.controls do
		if ( control ~= VideoOptionsEffectsPanelQualitySlider ) then
			control.newValue = nil;
		end
	end
end

function VideoOptionsEffectsPanel_Refresh (self)
	BlizzardOptionsPanel_Refresh(self);
	VideoOptionsEffectsPanel_UpdateVideoQuality();
	-- HACK: force update the quality slider because the update video quality call will change the new value
	VideoOptionsEffectsPanelQualitySlider.value = VideoOptionsEffectsPanelQualitySlider.newValue;
end

function VideoOptionsEffectsPanel_OnLoad (self)
	self.name = EFFECTS_LABEL;
	self.options = EffectsPanelOptions;
	VideoOptionsPanel_OnLoad(self, nil, nil, VideoOptionsEffectsPanel_Default, VideoOptionsEffectsPanel_Refresh);

	-- this must come AFTER the parent OnLoad because the functions will be set to defaults there
	self:SetScript("OnEvent", VideoOptionsEffectsPanel_OnEvent);
end

function VideoOptionsEffectsPanel_OnEvent (self, event, ...)
	BlizzardOptionsPanel_OnEvent(self, event, ...);

	if ( event == "PLAYER_ENTERING_WORLD" ) then
		-- fixup value steps for the farclip control, which has an adjustable min/max
		local farclipControl = VideoOptionsEffectsPanelViewDistance;
		local minValue, maxValue = farclipControl:GetMinMaxValues();
		farclipControl:SetValueStep((maxValue - minValue) / 10);

		-- some of the values in the preset graphics quality levels aren't available on all platforms, so we
		-- need to fixup the quality levels now
		VideoOptionsEffectsPanel_FixupQualityLevels();
		VideoOptionsEffectsPanel_UpdateVideoQuality();

		if ( not IsPlayerResolutionAvailable() ) then
			VideoOptionsEffectsPanelPlayerTexture:Disable();
		end
	end
end

function VideoOptionsEffectsPanel_SetVideoQuality (quality)
	if ( not quality or not GraphicsQualityLevels[quality] or VideoOptionsEffectsPanel.videoQuality == quality ) then
		return;
	elseif ( quality == VIDEO_OPTIONS_CUSTOM_QUALITY ) then
		VideoOptionsEffectsPanel.videoQuality = quality;
		VideoOptionsEffectsPanel_SetVideoQualityLabels(quality);
		return;
	end

	for control, value in next, GraphicsQualityLevels[quality] do
		control = _G[control];
		if ( control.type == CONTROLTYPE_SLIDER ) then
			control:SetDisplayValue(value);
		elseif ( control.type == CONTROLTYPE_CHECKBOX ) then
			if ( value ) then
				control:SetChecked(true);
			else
				control:SetChecked(false);
			end
			BlizzardOptionsPanel_CheckButton_SetNewValue(control);
		end
	end

	VideoOptionsEffectsPanel.videoQuality = quality;
	VideoOptionsEffectsPanel_SetVideoQualityLabels(quality);
end

function VideoOptionsEffectsPanel_SetVideoQualityLabels (quality)
	quality = quality or VIDEO_OPTIONS_CUSTOM_QUALITY;
	VideoOptionsEffectsPanelQualityLabel:SetFormattedText(VIDEO_QUALITY_S, _G["VIDEO_QUALITY_LABEL" .. quality]);
	VideoOptionsEffectsPanelQualitySubText:SetText(_G["VIDEO_QUALITY_SUBTEXT" .. quality]);
	VideoOptionsEffectsPanelQualitySlider:SetValue(quality);
end

function VideoOptionsEffectsPanel_GetVideoQuality ()
	for quality, controls in ipairs(GraphicsQualityLevels) do 
		local mismatch = false;
		for control, value in next, controls do
			control = _G[control];
			if ( control.type == CONTROLTYPE_CHECKBOX  ) then
				local checked = control:GetChecked();
				if ( ( value and not checked ) or ( not value and checked ) ) then
					mismatch = true;
					break;
				end
			elseif ( control.GetValue ) then
				if ( not (abs(control:GetValue() - value) <= VIDEO_OPTIONS_COMPARISON_EPSILON) ) then
					-- you may have been expecting ( control:GetValue() ~= value ) but here's why we can't use that:
					-- 1) floating point error: if we set a value to 0.4 and the machine's floating point error results in the value being 0.40000000596046 instead,
					--    we want those two values to be considered equal
					-- 2) NaN/IND numbers: if for whatever reason a control gives us an NaN or IND number, any comparisons with those numbers will evaluate to false,
					--    so we phrase the comparison inversely so NaN/IND comparisons result in a mismatch
					mismatch = true;
					break;
				end
			end
		end
		if ( not mismatch ) then
			return quality;
		end
	end

	return VIDEO_OPTIONS_CUSTOM_QUALITY;
end

function VideoOptionsEffectsPanel_SetCustomQuality ()
	for control in next, GraphicsQualityLevels[1] do
		control = _G[control];
		control:Enable();
	end
end

function VideoOptionsEffectsPanel_SetPresetQuality ()
	for control in next, GraphicsQualityLevels[1] do
		control = _G[control];
		control:Disable();
	end
end

function VideoOptionsEffectsPanel_UpdateVideoQuality ()
	local quality = VideoOptionsEffectsPanel_GetVideoQuality();
	if ( quality ~= VideoOptionsEffectsPanel.videoQuality ) then
		VideoOptionsEffectsPanel_SetVideoQuality(quality);
	end
end

function VideoOptionsEffectsPanelSlider_OnValueChanged (self, value)
	self.newValue = value;
	if(self:GetParent():IsVisible()) then
		VideoOptionsEffectsPanel_UpdateVideoQuality();
		VideoOptionsFrameApply:Enable();
	end
end

function VideoOptionsEffectsPanel_FixupQualityLevels ()
	-- set the lowest and highest
	for quality, controls in ipairs(GraphicsQualityLevels) do
		for index, value in next, controls do
			local control = _G[index];
			if ( control.type ~= CONTROLTYPE_CHECKBOX and control.cvar ) then
				local minValue = BlizzardOptionsPanel_GetCVarMinSafe(control.cvar);
				local maxValue = BlizzardOptionsPanel_GetCVarMaxSafe(control.cvar);
				if ( minValue and value < minValue ) then
					controls[index] = minValue;
				elseif ( maxValue and value > maxValue ) then
					controls[index] = maxValue;
				end
			end
		end
	end
end

--[[Stereo Options]]

VideoStereoPanelOptions = {
	gxStereoEnabled = { text = "ENABLE_STEREO_VIDEO" },
	gxStereoConvergence = { text = "DEPTH_CONVERGENCE", minValue = 0.2, maxValue = 50, valueStep = 0.1, tooltip = OPTION_STEREO_CONVERGENCE},
	gxStereoSeparation = { text = "EYE_SEPARATION", minValue = 0, maxValue = 100, valueStep = 1, tooltip = OPTION_STEREO_SEPARATION},
	gxCursor = { text = "STEREO_HARDWARE_CURSOR" },
}

function VideoOptionsStereoPanel_OnLoad (self)
	self.name = STEREO_VIDEO_LABEL;
	self.options = VideoStereoPanelOptions;
	if ( IsStereoVideoAvailable() ) then
		VideoOptionsPanel_OnLoad(self);
	end
	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	self:SetScript("OnEvent", VideoOptionsStereoPanel_OnEvent);
end

function VideoOptionsStereoPanel_Default(self)
	RestoreVideoStereoDefaults();
	for _, control in next, self.controls do
		if ( control.defaultValue and control.value ~= control.defaultValue ) then
			control:SetValue(control.defaultValue);
		end
		control.newValue = nil;
	end
end

function VideoOptionsStereoPanel_OnEvent(self, event, ...)
	BlizzardOptionsPanel_OnEvent(self, event, ...);
	
	if ( event == "PLAYER_ENTERING_WORLD" ) then
		-- don't allow systems that don't support features to enable them
		local anisotropic, pixelShaders, vertexShaders, trilinear, buffering, maxAnisotropy, hardwareCursor = GetVideoCaps();
		if ( not hardwareCursor ) then
			VideoOptionsStereoPanelHardwareCursor:SetChecked(false);
			VideoOptionsStereoPanelHardwareCursor:Disable();
		end
		VideoOptionsStereoPanelHardwareCursor.SetChecked =
			function (self, checked)
				local anisotropic, pixelShaders, vertexShaders, trilinear, buffering, maxAnisotropy, hardwareCursor = GetVideoCaps();
				if ( not hardwareCursor ) then
					checked = false;
				end
				getmetatable(self).__index.SetChecked(self, checked);
			end
		VideoOptionsStereoPanelHardwareCursor.Enable =
			function (self)
				local anisotropic, pixelShaders, vertexShaders, trilinear, buffering, maxAnisotropy, hardwareCursor = GetVideoCaps();
				if ( not hardwareCursor ) then
					return;
				end
				getmetatable(self).__index.Enable(self);
				local text = _G[self:GetName().."Text"];
				local fontObject = text:GetFontObject();
				_G[self:GetName().."Text"]:SetTextColor(fontObject:GetTextColor());
			end
	end
end


-- [[ New features panels (WotLKExtensions) ]] --
-- "Нововведения" (the presets) and its children: lighting, atmosphere, water, picture. Every control applies at
-- once (no Okay / Cancel); the controls are found by their name after "Panel" (VideoOptionsLightingPanelSsaoDropDown
-- -> SsaoDropDown)

FEATURES_LABEL = "Нововведения";
FEATURES_LABEL_SUBTEXT = "Готовые наборы всех эффектов. Каждый эффект настраивается в разделах ниже.";
FEATURES_LIGHTING = "Освещение";
FEATURES_LIGHTING_SUBTEXT = "Затенение, свечение, лучи солнца и тонмаппинг.";
FEATURES_ATMOSPHERE = "Атмосфера";
FEATURES_ATMOSPHERE_SUBTEXT = "Туман, дымка у земли и размытие дали.";
FEATURES_WATER = "Вода";
FEATURES_WATER_SUBTEXT = "Отражения, рябь и блик солнца на воде. Требует сглаживания (MSAA).";
FEATURES_PICTURE = "Изображение";
FEATURES_PICTURE_SUBTEXT = "Сглаживание FXAA и цветокоррекция.";

FOG_MODE = "Туман";
FOG_MODE_TOOLTIP = "Дальность тумана: как в клиенте, в три раза дальше или без тумана.";
FOG_MODES = { [0] = "Обычный", "Дальше", "Выключен" };
SSAO_MODE = "Затенение (SSAO)";
SSAO_MODE_TOOLTIP = "Мягкие тени в углах, щелях и под предметами. Требует сглаживания (MSAA).";
SSAO_MODES = { [0] = "Выключено", "Включено" };
BLOOM_MODE = "Свечение (Bloom)";
BLOOM_MODE_TOOLTIP = "Мягкий ореол вокруг ярких мест: огней, окон, эффектов.";
GODRAYS_MODE = "Лучи солнца";
GODRAYS_MODE_TOOLTIP = "Лучи света от солнца сквозь деревья и края гор. Требует сглаживания (MSAA).";
FXAA_MODE = "Сглаживание FXAA";
FXAA_MODE_TOOLTIP = "Сглаживает края после отрисовки: почти бесплатно, работает и без MSAA.";
TONEMAP_MODE = "Тонмаппинг";
TONEMAP_MODE_TOOLTIP = "Кинематографичная кривая: мягкие светлые места вместо резкого белого.";
GROUND_FOG_MODE = "Туман у земли";
GROUND_FOG_MODE_TOOLTIP = "Дымка в низинах и над водой - ниже вашего персонажа. Требует сглаживания (MSAA).";
SSR_MODE = "Отражения в воде";
SSR_MODE_TOOLTIP = "Вода отражает горы, деревья и здания (то, что видно на экране). Требует сглаживания (MSAA).";
DOF_MODE = "Глубина резкости";
DOF_MODE_TOOLTIP = "Даль размывается, персонаж и всё рядом остаётся резким. Требует сглаживания (MSAA).";

SSAO_STRENGTH = "Сила затенения";
SSAO_RADIUS = "Радиус затенения";
BLOOM_STRENGTH = "Сила свечения";
BLOOM_THRESHOLD = "Порог свечения";
GODRAYS_STRENGTH = "Сила лучей";
TONEMAP_EXPOSURE = "Экспозиция";
GROUND_FOG_DENSITY = "Плотность дымки";
GROUND_FOG_HEIGHT = "Высота дымки";
DOF_STRENGTH = "Сила размытия";
DOF_DISTANCE = "Дальность размытия";
SSR_STRENGTH = "Сила отражений";
SSR_RIPPLE = "Рябь на воде";
SSR_SUN = "Блик солнца";
COLOR_CONTRAST = "Контраст";
COLOR_SATURATION = "Насыщенность";
COLOR_BRIGHTNESS = "Яркость";
COLOR_SHARPEN = "Резкость";
VIGNETTE = "Виньетка";
FILM_GRAIN = "Зерно";

FEATURES_PRESET_OFF = "Выкл";
FEATURES_PRESET_SOFT = "Мягко";
FEATURES_PRESET_RETAIL = "Ретейл";
FEATURES_PRESET_MAX = "Максимум";

local FEATURE_DROPDOWNS = {
	FogDropDown = { cvar = "fogMode", modes = "FOG_MODES" },
	SsaoDropDown = { cvar = "ssao", modes = "SSAO_MODES" },
	BloomDropDown = { cvar = "bloom", modes = "SSAO_MODES" },
	GodRaysDropDown = { cvar = "godRays", modes = "SSAO_MODES" },
	DofDropDown = { cvar = "dof", modes = "SSAO_MODES" },
	SsrDropDown = { cvar = "ssr", modes = "SSAO_MODES" },
	FxaaDropDown = { cvar = "fxaa", modes = "SSAO_MODES" },
	TonemapDropDown = { cvar = "tonemap", modes = "SSAO_MODES" },
	GroundFogDropDown = { cvar = "groundFog", modes = "SSAO_MODES" },
};

local FEATURE_SLIDERS = {
	SsaoStrength = { cvar = "ssaoStrength", text = "SSAO_STRENGTH", minValue = 0, maxValue = 2, valueStep = 0.1 },
	SsaoRadius = { cvar = "ssaoRadius", text = "SSAO_RADIUS", minValue = 0.3, maxValue = 5, valueStep = 0.1 },
	BloomStrength = { cvar = "bloomStrength", text = "BLOOM_STRENGTH", minValue = 0, maxValue = 2, valueStep = 0.1 },
	BloomThreshold = { cvar = "bloomThreshold", text = "BLOOM_THRESHOLD", minValue = 0.3, maxValue = 1, valueStep = 0.05 },
	GodRaysStrength = { cvar = "godRaysStrength", text = "GODRAYS_STRENGTH", minValue = 0, maxValue = 2, valueStep = 0.1 },
	TonemapExposure = { cvar = "tonemapExposure", text = "TONEMAP_EXPOSURE", minValue = 0.5, maxValue = 3, valueStep = 0.1 },
	GroundFogDensity = { cvar = "groundFogDensity", text = "GROUND_FOG_DENSITY", minValue = 0, maxValue = 1, valueStep = 0.05 },
	GroundFogHeight = { cvar = "groundFogHeight", text = "GROUND_FOG_HEIGHT", minValue = 0, maxValue = 30, valueStep = 1 },
	DofStrength = { cvar = "dofStrength", text = "DOF_STRENGTH", minValue = 0, maxValue = 1, valueStep = 0.05 },
	DofDistance = { cvar = "dofDistance", text = "DOF_DISTANCE", minValue = 5, maxValue = 300, valueStep = 5 },
	SsrStrength = { cvar = "ssrStrength", text = "SSR_STRENGTH", minValue = 0, maxValue = 1, valueStep = 0.05 },
	SsrRipple = { cvar = "ssrRipple", text = "SSR_RIPPLE", minValue = 0, maxValue = 1, valueStep = 0.05 },
	SsrSun = { cvar = "ssrSun", text = "SSR_SUN", minValue = 0, maxValue = 2, valueStep = 0.1 },
	ColorContrast = { cvar = "colorContrast", text = "COLOR_CONTRAST", minValue = 0.5, maxValue = 1.5, valueStep = 0.05 },
	ColorSaturation = { cvar = "colorSaturation", text = "COLOR_SATURATION", minValue = 0, maxValue = 2, valueStep = 0.05 },
	ColorBrightness = { cvar = "colorBrightness", text = "COLOR_BRIGHTNESS", minValue = 0.5, maxValue = 1.5, valueStep = 0.05 },
	ColorSharpen = { cvar = "colorSharpen", text = "COLOR_SHARPEN", minValue = 0, maxValue = 1, valueStep = 0.05 },
	Vignette = { cvar = "vignette", text = "VIGNETTE", minValue = 0, maxValue = 1, valueStep = 0.05 },
	FilmGrain = { cvar = "filmGrain", text = "FILM_GRAIN", minValue = 0, maxValue = 1, valueStep = 0.05 },
};

local FEATURE_PRESETS = {
	PresetOff = {
		ssao = 0, bloom = 0, godRays = 0, dof = 0, ssr = 0, fxaa = 0, tonemap = 0, groundFog = 0,
		colorContrast = 1, colorSaturation = 1, colorBrightness = 1, colorSharpen = 0, vignette = 0, filmGrain = 0,
	},
	PresetSoft = {
		ssao = 1, ssaoStrength = 0.8, ssaoRadius = 1.5, bloom = 1, bloomStrength = 0.4, bloomThreshold = 0.8,
		godRays = 1, godRaysStrength = 0.7, dof = 0, ssr = 1, ssrStrength = 0.6, ssrRipple = 0.4, ssrSun = 0.8,
		fxaa = 1, tonemap = 0, groundFog = 0,
		colorContrast = 1.05, colorSaturation = 1.05, colorBrightness = 1, colorSharpen = 0.1, vignette = 0.2, filmGrain = 0,
	},
	PresetRetail = {
		ssao = 1, ssaoStrength = 1, ssaoRadius = 1.5, bloom = 1, bloomStrength = 0.6, bloomThreshold = 0.7,
		godRays = 1, godRaysStrength = 1, dof = 1, dofStrength = 0.6, dofDistance = 80,
		ssr = 1, ssrStrength = 0.8, ssrRipple = 0.5, ssrSun = 1,
		fxaa = 1, tonemap = 1, tonemapExposure = 1.4, groundFog = 1, groundFogDensity = 0.4, groundFogHeight = 4,
		colorContrast = 1.1, colorSaturation = 1.1, colorBrightness = 1, colorSharpen = 0.2, vignette = 0.3, filmGrain = 0,
	},
	PresetMax = {
		ssao = 1, ssaoStrength = 1.5, ssaoRadius = 2, bloom = 1, bloomStrength = 0.9, bloomThreshold = 0.6,
		godRays = 1, godRaysStrength = 1.5, dof = 1, dofStrength = 1, dofDistance = 60,
		ssr = 1, ssrStrength = 1, ssrRipple = 0.6, ssrSun = 1.5,
		fxaa = 1, tonemap = 1, tonemapExposure = 1.6, groundFog = 1, groundFogDensity = 0.6, groundFogHeight = 6,
		colorContrast = 1.15, colorSaturation = 1.2, colorBrightness = 1, colorSharpen = 0.4, vignette = 0.4, filmGrain = 0.2,
	},
};

local FEATURE_SUBPANELS = {
	VideoOptionsLightingPanel = "FEATURES_LIGHTING",
	VideoOptionsAtmospherePanel = "FEATURES_ATMOSPHERE",
	VideoOptionsWaterPanel = "FEATURES_WATER",
	VideoOptionsPicturePanel = "FEATURES_PICTURE",
};

local featureControls = {};		-- the shown ones: a preset refreshes them

local function FeatureKey (self)
	return self:GetName():match("Panel(.+)$");
end

-- a cvar of the DLL that isn't there yet (an older build, or not in the glue cvar list): made here, so the
-- control works; the DLL finds it by name
local function FeatureSetCVar (cvar, value)
	if ( GetCVar(cvar) == nil ) then
		RegisterCVar(cvar, value);
	end
	SetCVar(cvar, value);
end

local function FeaturePanel_Setup (self, name)
	self.name = name;
	self.options = {};
	self.controls = {};	-- none registered (the controls apply at once): Okay / Cancel / Refresh walk this table
	VideoOptionsPanel_OnLoad(self);
end

function VideoOptionsFeaturesPanel_OnLoad (self)
	FeaturePanel_Setup(self, FEATURES_LABEL);
end

function VideoOptionsFeaturesSubPanel_OnLoad (self)
	self.parent = FEATURES_LABEL;
	FeaturePanel_Setup(self, _G[FEATURE_SUBPANELS[self:GetName()]]);
end

local function FeatureDropDown_Initialize (self)
	local setup = FEATURE_DROPDOWNS[FeatureKey(self)];
	local modes = _G[setup.modes];
	local current = GetCVar(setup.cvar) or "0";
	local info = UIDropDownMenu_CreateInfo();
	for mode = 0, #modes do
		info.text = modes[mode];
		info.value = tostring(mode);
		info.checked = ( info.value == current ) and 1 or nil;
		info.func = function (button)
			FeatureSetCVar(setup.cvar, button.value);
			UIDropDownMenu_SetSelectedValue(self, button.value);
		end;
		UIDropDownMenu_AddButton(info);
	end
end

function VideoOptionsFeaturesPanelDropDown_OnShow (self)
	featureControls[self] = VideoOptionsFeaturesPanelDropDown_OnShow;
	UIDropDownMenu_SetWidth(self, 110);
	UIDropDownMenu_Initialize(self, FeatureDropDown_Initialize);
	UIDropDownMenu_SetSelectedValue(self, GetCVar(FEATURE_DROPDOWNS[FeatureKey(self)].cvar) or "0");
end

function VideoOptionsFeaturesPanelSlider_OnLoad (self)
	local setup = FEATURE_SLIDERS[FeatureKey(self)];
	local name = self:GetName();
	_G[name.."Text"]:SetText(_G[setup.text]);
	_G[name.."Low"]:SetText(setup.minValue);
	_G[name.."High"]:SetText(setup.maxValue);
	self:SetMinMaxValues(setup.minValue, setup.maxValue);
	self:SetValueStep(setup.valueStep);
end

function VideoOptionsFeaturesPanelSlider_OnShow (self)
	featureControls[self] = VideoOptionsFeaturesPanelSlider_OnShow;
	local setup = FEATURE_SLIDERS[FeatureKey(self)];
	self.loading = true;
	self:SetValue(tonumber(GetCVar(setup.cvar)) or setup.minValue);
	self.loading = nil;
end

function VideoOptionsFeaturesPanelSlider_OnValueChanged (self, value)
	if ( not self.loading ) then
		FeatureSetCVar(FEATURE_SLIDERS[FeatureKey(self)].cvar, value);
	end
end

-- presets: every effect at once (the fog stays as it is)
function VideoOptionsFeaturesPanelPreset_OnClick (self)
	for cvar, value in pairs(FEATURE_PRESETS[FeatureKey(self)]) do
		FeatureSetCVar(cvar, value);
	end
	for control, refresh in pairs(featureControls) do
		refresh(control);
	end
end
