-- Константы системы меню (из ретейловых MenuConstants.lua).
MenuConstants = {
	VerticalLinearDirection = 1,
	ElementPollFrequencySeconds = 0.2,
};

MenuResponse = {
	Open = 1,		-- меню остаётся открытым
	Refresh = 2,	-- перерисовать элементы
	Close = 3,		-- закрыть это меню
	CloseAll = 4,	-- закрыть все меню
};

MenuInputContext = {
	None = 1,
	MouseButton = 2,
	MouseWheel = 3,
};

MenuCloseReason = {
	Unspecified = 1,
	CloseAll = 2,
};

-- атласы кнопки-стрелки (ретейл)
WowStyle1FilterDropdownStateDownOver = "common-dropdown-b-button-pressedhover";
WowStyle1FilterDropdownStateOver = "common-dropdown-b-button-hover";
WowStyle1FilterDropdownStateDown = "common-dropdown-b-button-pressed";
WowStyle1FilterDropdownStateOpen = "common-dropdown-b-button-open";
WowStyle1FilterDropdownStateEnabled = "common-dropdown-b-button";
WowStyle1FilterDropdownStateDisabled = "common-dropdown-b-button-disabled";
