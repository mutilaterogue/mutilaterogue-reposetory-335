-- Holy Power on the player frame (Cataclysm's PaladinPowerBar, 3.3.5a: three runes). The value: ClassPower.lua.
HOLY_POWER_FULL = 3;
PALADINPOWERBAR_SHOW_LEVEL = 10;

function PaladinPowerBar_ToggleHolyRune(rune, visible)
	if ( visible ) then
		rune.deactivate:Stop();
		rune.activate:Play();
	else
		rune.activate:Stop();
		rune.deactivate:Play();
	end
end

function PaladinPowerBar_Update(self)
	local numHolyPower = UnitPower(self:GetParent().unit or "player", SPELL_POWER_HOLY_POWER);
	for i = 1, HOLY_POWER_FULL do
		local rune = _G[self:GetName().."Rune"..i];
		local isShown = rune:GetAlpha() > 0 or rune.activate:IsPlaying();
		local shouldShow = i <= numHolyPower;
		if ( isShown ~= shouldShow ) then
			PaladinPowerBar_ToggleHolyRune(rune, shouldShow);
		end
	end

	-- the bar flashes when it is full
	if ( numHolyPower >= HOLY_POWER_FULL ) then
		self.glow.pulse.stopPulse = false;
		self.glow.pulse:Play();
	else
		self.glow.pulse.stopPulse = true;
	end
end

function PaladinPowerBar_OnLoad(self)
	local _, class = UnitClass("player");
	if ( class ~= "PALADIN" ) then
		self:Hide();
		return;
	end
	if ( UnitLevel("player") < PALADINPOWERBAR_SHOW_LEVEL ) then
		self:RegisterEvent("PLAYER_LEVEL_UP");
		self:SetAlpha(0);
	end
	self.glow:SetAlpha(0);
	for i = 1, HOLY_POWER_FULL do
		_G[self:GetName().."Rune"..i]:SetAlpha(0);
	end
	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	self:RegisterEvent("UNIT_DISPLAYPOWER");
end

function PaladinPowerBar_OnEvent(self, event, arg1)
	if ( event == "PLAYER_LEVEL_UP" ) then
		if ( arg1 >= PALADINPOWERBAR_SHOW_LEVEL ) then
			self:UnregisterEvent("PLAYER_LEVEL_UP");
			self.showAnim:Play();
			PaladinPowerBar_Update(self);
		end
	else
		PaladinPowerBar_Update(self);
	end
end
