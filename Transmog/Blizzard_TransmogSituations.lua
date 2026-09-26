-- Трансмогрификация: вкладка «Ситуации» (ретейл: TransmogWardrobeSituationsMixin) - когда выбранный наряд надевается сам.
-- В 3.3.5 нет TransmogSituation.db2, условия свои (server/transmog_outfits.cpp):
--   местность: 0 любая, 1 город/таверна, 2 открытый мир, 3 подземелье, 4 рейд, 5 поле боя/арена
--   передвижение: 0 любое, 1 верхом, 2 пешком;  бой: 0 любой, 1 в бою, 2 вне боя
--   "TMOG_OUTFIT_SIT" : outfitId : enabled : location : movement : combat

local SITUATIONS = {
	{ key = "location", title = "TRANSMOG_SITUATION_LOCATION", options = 5, prefix = "TRANSMOG_SITUATION_LOCATION_" },
	{ key = "movement", title = "TRANSMOG_SITUATION_MOVEMENT", options = 2, prefix = "TRANSMOG_SITUATION_MOVEMENT_" },
	{ key = "combat",   title = "TRANSMOG_SITUATION_COMBAT",   options = 2, prefix = "TRANSMOG_SITUATION_COMBAT_" },
};

local function OptionText(situation, value)
	if value == 0 then
		return TRANSMOG_SITUATION_ANY;
	end
	return _G[situation.prefix .. value];
end

local function GetSituationsFrame()
	return TransmogFrame.WardrobeCollection.TabContent.SituationsFrame;
end

local function HasOptions(edit)
	return edit.location ~= 0 or edit.movement ~= 0 or edit.combat ~= 0;
end

local function IsDirty(self)
	local outfit = TransmogFrame.selectedOutfit;
	local edit = self.edit;
	if not outfit or not edit then
		return false;
	end
	local saved = outfit.situations;
	return saved.enabled ~= edit.enabled or saved.location ~= edit.location or saved.movement ~= edit.movement or saved.combat ~= edit.combat;
end

function TransmogSituation_OnLoad(self)
	local situation = SITUATIONS[self:GetID()];
	self.situation = situation;
	self.Title:SetText(_G[situation.title]);
	self.Dropdown:SetupMenu(function(dropdown, rootDescription)
		local frame = GetSituationsFrame();
		for value = 0, situation.options do
			rootDescription:CreateRadio(OptionText(situation, value), function()
				return frame.edit and frame.edit[situation.key] == value;
			end, function()
				if frame.edit then
					frame.edit[situation.key] = value;
					if value ~= 0 then
						frame.edit.enabled = true;
					end
					TransmogSituationsFrame_UpdateControls(frame);
				end
			end);
		end
	end);
end

function TransmogSituationsFrame_OnLoad(self)
	local label = _G[self.EnabledToggle:GetName() .. "Text"];
	if label then
		label:SetFontObject(GameFontNormal);
		label:SetText(TRANSMOG_SITUATIONS_ENABLED);
	end
end

function TransmogSituationsFrame_UpdateControls(self)
	local outfit = TransmogFrame.selectedOutfit;
	local edit = self.edit;
	self.EnabledToggle:SetChecked(edit and edit.enabled);
	for _, row in ipairs({ self.Situations.Location, self.Situations.Movement, self.Situations.Combat }) do
		if row.Dropdown.GenerateMenu then
			row.Dropdown:GenerateMenu();
		elseif row.Dropdown.SetText and edit then
			row.Dropdown:SetText(OptionText(row.situation, edit[row.situation.key]));
		end
	end
	local canApply = outfit and IsDirty(self) and (not edit.enabled or HasOptions(edit));
	self.ApplyButton:SetEnabled(canApply);
	self.UndoButton:SetShown(IsDirty(self));
end

-- показать ситуации выбранного наряда
function TransmogSituationsFrame_Refresh(self)
	local outfit = TransmogFrame.selectedOutfit;
	local hasOutfit = outfit ~= nil;
	self.NoOutfitText:SetShown(not hasOutfit);
	for _, region in ipairs({ self.DescriptionText, self.OutfitName, self.DefaultsButton, self.Situations, self.EnabledToggle, self.ApplyButton, self.UndoButton }) do
		region:SetShown(hasOutfit);
	end
	if not hasOutfit then
		self.edit = nil;
		return;
	end
	if self.editOutfit ~= outfit or not IsDirty(self) then
		local saved = outfit.situations;
		self.edit = { enabled = saved.enabled, location = saved.location, movement = saved.movement, combat = saved.combat };
		self.editOutfit = outfit;
	end
	self.OutfitName:SetText(outfit.name);
	TransmogSituationsFrame_UpdateControls(self);
end

function TransmogSituationsFrame_ToggleEnabled(button)
	local self = GetSituationsFrame();
	if self.edit then
		self.edit.enabled = button:GetChecked() and true or false;
		TransmogSituationsFrame_UpdateControls(self);
	end
end

function TransmogSituationsFrame_SetDefaults()
	local self = GetSituationsFrame();
	if self.edit then
		self.edit.enabled, self.edit.location, self.edit.movement, self.edit.combat = false, 0, 0, 0;
		TransmogSituationsFrame_UpdateControls(self);
	end
end

function TransmogSituationsFrame_Undo()
	local self = GetSituationsFrame();
	self.editOutfit = nil;
	TransmogSituationsFrame_Refresh(self);
end

function TransmogSituationsFrame_Apply()
	local self = GetSituationsFrame();
	local outfit, edit = TransmogFrame.selectedOutfit, self.edit;
	if not outfit or not edit or not Comm_Send then
		return;
	end
	PlaySound("igMainMenuOptionCheckBoxOn");
	Comm_Send(TransmogUI.OP_OUTFIT_SIT, outfit.id, edit.enabled and 1 or 0, edit.location, edit.movement, edit.combat);
	-- сервер пришлёт обновлённый список нарядов
	outfit.situations = { enabled = edit.enabled and HasOptions(edit), location = edit.location, movement = edit.movement, combat = edit.combat };
	TransmogSituationsFrame_UpdateControls(self);
end

function TransmogSituationsFrame_ApplyOnEnter(button)
	local self = GetSituationsFrame();
	if button:IsEnabled() ~= 1 and self.edit and self.edit.enabled and not HasOptions(self.edit) then
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
		GameTooltip:SetText(TRANSMOG_SITUATIONS_APPLY_DISABLED_TOOLTIP, 1, 0.1, 0.1, 1, true);
		GameTooltip:Show();
	end
end
