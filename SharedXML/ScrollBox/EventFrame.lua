-- EventFrame / EventButton (ретейл) для 3.3.5a.
-- В ретейле это "intrinsic"-типы фреймов: их OnLoad/OnShow/... вызываются движком всегда,
-- даже если наследник переопределил скрипт. В 3.3.5 такого нет, поэтому:
--   * реестр колбэков инициализируется лениво (при первом RegisterCallback/TriggerEvent);
--   * "postcall"-скрипты вешаются через HookScript — он вызывается после основного обработчика.

local function MakeIntrinsicMixin(events, forwarders)
	local mixin = CreateFromMixins(CallbackRegistryMixin);
	mixin:GenerateCallbackEvents(events);

	local function Ensure(self)
		if self.intrinsicInitialized then
			return;
		end
		self.intrinsicInitialized = true;
		CallbackRegistryMixin.OnLoad(self);
		if self.HookScript then
			for script, method in pairs(forwarders) do
				self:HookScript(script, function(frame, ...)
					frame[method](frame, ...);
				end);
			end
		end
	end
	mixin.EnsureIntrinsic = Ensure;

	function mixin:OnLoad_Intrinsic()
		Ensure(self);
	end

	function mixin:RegisterCallback(...)
		Ensure(self);
		return CallbackRegistryMixin.RegisterCallback(self, ...);
	end

	function mixin:RegisterCallbackWithHandle(...)
		Ensure(self);
		return CallbackRegistryMixin.RegisterCallbackWithHandle(self, ...);
	end

	function mixin:UnregisterCallback(...)
		if self.intrinsicInitialized then
			return CallbackRegistryMixin.UnregisterCallback(self, ...);
		end
	end

	function mixin:TriggerEvent(...)
		if self.intrinsicInitialized then
			return CallbackRegistryMixin.TriggerEvent(self, ...);
		end
	end

	return mixin;
end

EventFrameMixin = MakeIntrinsicMixin(
	{ "OnHide", "OnShow", "OnSizeChanged" },
	{ OnHide = "OnHide_Intrinsic", OnShow = "OnShow_Intrinsic", OnSizeChanged = "OnSizeChanged_Intrinsic" }
);

function EventFrameMixin:OnHide_Intrinsic()
	self:TriggerEvent("OnHide");
end

function EventFrameMixin:OnShow_Intrinsic()
	self:TriggerEvent("OnShow");
end

function EventFrameMixin:OnSizeChanged_Intrinsic(width, height)
	self:TriggerEvent("OnSizeChanged", width, height);
end

EventButtonMixin = MakeIntrinsicMixin(
	{ "OnMouseUp", "OnMouseDown", "OnClick", "OnEnter", "OnLeave", "OnSizeChanged" },
	{
		OnMouseUp = "OnMouseUp_Intrinsic",
		OnMouseDown = "OnMouseDown_Intrinsic",
		OnClick = "OnClick_Intrinsic",
		OnEnter = "OnEnter_Intrinsic",
		OnLeave = "OnLeave_Intrinsic",
		OnSizeChanged = "OnSizeChanged_Intrinsic",
	}
);

local function PlaySoundKit(button, soundKitID)
	if soundKitID and button:IsEnabled() then
		PlaySound(soundKitID);
	end
end

function EventButtonMixin:OnMouseUp_Intrinsic(buttonName, upInside)
	-- 3.3.5 не передаёт upInside
	if upInside == nil then
		upInside = self:IsMouseOver();
	end
	self:TriggerEvent("OnMouseUp", buttonName, upInside);
	PlaySoundKit(self, self.mouseUpSoundKitID);
end

function EventButtonMixin:OnMouseDown_Intrinsic(buttonName)
	if self:IsEnabled() then
		self:TriggerEvent("OnMouseDown", buttonName);
		PlaySoundKit(self, self.mouseDownSoundKitID);
	end
end

function EventButtonMixin:OnClick_Intrinsic(buttonName, down)
	if self:IsEnabled() then
		self:TriggerEvent("OnClick", buttonName, down);
		PlaySoundKit(self, self.clickSoundKitID);
	end
end

function EventButtonMixin:OnEnter_Intrinsic()
	if self:IsEnabled() then
		self:TriggerEvent("OnEnter");
	end
end

function EventButtonMixin:OnLeave_Intrinsic()
	self:TriggerEvent("OnLeave");
end

function EventButtonMixin:OnSizeChanged_Intrinsic(width, height)
	self:TriggerEvent("OnSizeChanged", width, height);
end

-- для XML: шаблоны вместо intrinsic-тегов <EventFrame>/<EventButton>
-- (миксин навешивается XMLExt; инициализация — лениво, см. выше)
