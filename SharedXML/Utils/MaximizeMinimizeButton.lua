-- MaximizeMinimizeButtonFrame (упрощённый, API как в Midnight)
MaximizeMinimizeButtonFrameMixin = {};

function MaximizeMinimizeButtonFrameMixin:OnLoad()
	self.isMinimized = false;
	self.MaximizeButton:SetScript("OnClick", function() self:Maximize(); end);
	self.MinimizeButton:SetScript("OnClick", function() self:Minimize(); end);
end

function MaximizeMinimizeButtonFrameMixin:SetOnMaximizedCallback(callback)
	self.maximizedCallback = callback;
end

function MaximizeMinimizeButtonFrameMixin:SetOnMinimizedCallback(callback)
	self.minimizedCallback = callback;
end

function MaximizeMinimizeButtonFrameMixin:SetMinimizedCVar(cvar)
	self.cvar = cvar;
end

function MaximizeMinimizeButtonFrameMixin:SkipResetOnShow(skip)
	self.skipResetOnShow = skip;
end

function MaximizeMinimizeButtonFrameMixin:IsMinimized()
	return self.isMinimized;
end

function MaximizeMinimizeButtonFrameMixin:UpdateButtons()
	self.MaximizeButton:SetShown(self.isMinimized);
	self.MinimizeButton:SetShown(not self.isMinimized);
end

function MaximizeMinimizeButtonFrameMixin:Minimize(isAutomaticAction, skipCallback)
	self.isMinimized = true;
	self:UpdateButtons();
	if not isAutomaticAction and self.cvar then
		_G[self.cvar] = true;
	end
	if not skipCallback and self.minimizedCallback then
		self.minimizedCallback(self);
	end
end

function MaximizeMinimizeButtonFrameMixin:Maximize(isAutomaticAction, skipCallback)
	self.isMinimized = false;
	self:UpdateButtons();
	if not isAutomaticAction and self.cvar then
		_G[self.cvar] = false;
	end
	if not skipCallback and self.maximizedCallback then
		self.maximizedCallback(self);
	end
end
