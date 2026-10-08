-- C_EditMode для 3.3.5a: раскладки Edit Mode и настройки аккаунта.
-- Хранение через WriteCustomFile (файл на персонажа), как у профилей рейд-фреймов.

Enum = Enum or {};

Enum.EditModeLayoutType = Enum.EditModeLayoutType or {
	Preset = 0,
	Account = 1,
	Character = 2,
	Override = 3,
};

Enum.EditModeAccountSetting = Enum.EditModeAccountSetting or {
	ShowGrid = 0,
	GridSpacing = 1,
	SettingsExpanded = 2,
	EnableSnap = 19,
};

C_EditMode = C_EditMode or {};

local SAVE_VERSION = 1;

local layouts = nil;      -- массив раскладок
local activeLayout = 1;
local accountSettings = { [Enum.EditModeAccountSetting.ShowGrid] = 1, [Enum.EditModeAccountSetting.EnableSnap] = 1 };
local loadedFor = nil;

---------------------------------------------------------------------------
-- файл
---------------------------------------------------------------------------
local function PlayerReady()
	local name = UnitName("player");
	return name and name ~= "" and name ~= UNKNOWNOBJECT and name ~= "Unknown";
end

local function GetFileName()
	local name = UnitName("player") or "unknown";
	local realm = GetRealmName() or "unknown";
	return (("EditMode_%s_%s"):format(realm, name):gsub("[<>:\"/\\|%?%*]", "_"));
end

local function Serialize(value, out)
	local valueType = type(value);

	if valueType == "table" then
		out[#out + 1] = "{";
		for key, inner in pairs(value) do
			out[#out + 1] = "[";
			Serialize(key, out);
			out[#out + 1] = "]=";
			Serialize(inner, out);
			out[#out + 1] = ",";
		end
		out[#out + 1] = "}";
	elseif valueType == "string" then
		out[#out + 1] = string.format("%q", value);
	elseif valueType == "number" or valueType == "boolean" then
		out[#out + 1] = tostring(value);
	else
		out[#out + 1] = "nil";
	end
end

-- the built-in layouts, as retail's Modern / Classic presets: every character starts with them (a copy it can edit)
-- "Современная": the frames where the modern UI puts them; "Классическая": the 3.3.5 places (no system moved)
local MODERN_LAYOUT_NAME = "Современная";
local CLASSIC_LAYOUT_NAME = "Классическая";
local MODERN_SYSTEMS = {
	{ name = "PlayerFrame", point = "BOTTOMLEFT", x = 549.33340153821, y = 216.0000519743, settings = {} },
	{ name = "TargetFrame", point = "BOTTOMRIGHT", x = -549.33340153821, y = 216.0000519743, settings = {} },
	{ name = "CastingBarFrame", point = "BOTTOM", x = 0, y = 200.00005525689, settings = {} },
	{ name = "ObjectiveTrackerFrame", point = "TOPRIGHT", x = -105.33341822469, y = -205.99996867864, settings = {} },
	{ name = "BackpackFrame", point = "BOTTOMRIGHT", x = -3.3333581806971, y = 40.000044314931, settings = {} },
};

local function CopyLayoutTable(value)
	if type(value) ~= "table" then
		return value;
	end
	local copy = {};
	for key, inner in pairs(value) do
		copy[key] = CopyLayoutTable(inner);
	end
	return copy;
end

local function CreateModernLayout()
	return {
		layoutName = MODERN_LAYOUT_NAME,
		layoutType = Enum.EditModeLayoutType.Preset,
		systems = CopyLayoutTable(MODERN_SYSTEMS),
	};
end

local function CreateClassicLayout()
	return {
		layoutName = CLASSIC_LAYOUT_NAME,
		layoutType = Enum.EditModeLayoutType.Preset,
		systems = {},
	};
end

local function CreateDefaultLayouts()
	return { CreateModernLayout(), CreateClassicLayout() };
end

-- a character saved before the presets: they join its layouts (its own ones and its choice stay)
local function AddMissingPresets()
	local hasModern, hasClassic;
	for _, layout in ipairs(layouts) do
		if layout.layoutName == MODERN_LAYOUT_NAME then
			hasModern = true;
		elseif layout.layoutName == CLASSIC_LAYOUT_NAME then
			hasClassic = true;
		end
	end
	if not hasModern then
		table.insert(layouts, CreateModernLayout());
	end
	if not hasClassic then
		table.insert(layouts, CreateClassicLayout());
	end
end

local function Save()
	if not (layouts and WriteCustomFile and PlayerReady()) then
		return;
	end

	local out = {};
	Serialize({
		version = SAVE_VERSION,
		layouts = layouts,
		activeLayout = activeLayout,
		accountSettings = accountSettings,
	}, out);

	pcall(WriteCustomFile, GetFileName(), "return " .. table.concat(out));
end

local function Load()
	if not PlayerReady() then
		return;
	end

	local fileName = GetFileName();
	if layouts and loadedFor == fileName then
		return;
	end

	layouts = CreateDefaultLayouts();
	activeLayout = 1;
	loadedFor = fileName;

	if not (ReadCustomFile and CustomFileExists) then
		return;
	end

	local okExists, exists = pcall(CustomFileExists, fileName);
	if not (okExists and exists) then
		return;
	end

	local okRead, content = pcall(ReadCustomFile, fileName);
	if not (okRead and type(content) == "string") then
		return;
	end

	local chunk = loadstring(content);
	if not chunk then
		return;
	end
	setfenv(chunk, {});

	local okRun, data = pcall(chunk);
	if not (okRun and type(data) == "table") then
		return;
	end

	if type(data.layouts) == "table" and #data.layouts > 0 then
		layouts = data.layouts;
	end
	if type(data.activeLayout) == "number" then
		activeLayout = data.activeLayout;
	end
	if type(data.accountSettings) == "table" then
		accountSettings = data.accountSettings;
	end

	AddMissingPresets();
	if not layouts[activeLayout] then
		activeLayout = 1;
	end
end

---------------------------------------------------------------------------
-- события
---------------------------------------------------------------------------
local callbacks = {};

function C_EditMode.RegisterCallback(event, func)
	callbacks[event] = callbacks[event] or {};
	table.insert(callbacks[event], func);
end

local function FireEvent(event, ...)
	for _, func in ipairs(callbacks[event] or {}) do
		local ok, err = pcall(func, ...);
		if not ok then
			geterrorhandler()(err);
		end
	end
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
function C_EditMode.GetLayouts()
	Load();
	return { layouts = layouts or CreateDefaultLayouts(), activeLayout = activeLayout };
end

function C_EditMode.SaveLayouts(saveInfo)
	Load();

	if saveInfo then
		if type(saveInfo.layouts) == "table" then
			layouts = saveInfo.layouts;
		end
		if type(saveInfo.activeLayout) == "number" then
			activeLayout = saveInfo.activeLayout;
		end
	end

	Save();
	FireEvent("EDIT_MODE_LAYOUTS_UPDATED", layouts, activeLayout);
end

function C_EditMode.SetActiveLayout(index)
	Load();

	if not layouts or not layouts[index] then
		return;
	end

	activeLayout = index;
	Save();
	FireEvent("EDIT_MODE_LAYOUTS_UPDATED", layouts, activeLayout);
end

function C_EditMode.AddLayout(layoutName, copyFromIndex)
	Load();

	local source = copyFromIndex and layouts[copyFromIndex];
	local layout = {
		layoutName = layoutName or ("Раскладка " .. (#layouts + 1)),
		layoutType = Enum.EditModeLayoutType.Character,
		systems = source and CopyTable(source.systems or {}) or {},
	};

	table.insert(layouts, layout);
	activeLayout = #layouts;
	Save();
	FireEvent("EDIT_MODE_LAYOUTS_UPDATED", layouts, activeLayout);

	return activeLayout;
end

function C_EditMode.DeleteLayout(index)
	Load();

	if not layouts[index] or #layouts <= 1 then
		return;
	end

	table.remove(layouts, index);
	activeLayout = 1;
	Save();
	FireEvent("EDIT_MODE_LAYOUTS_UPDATED", layouts, activeLayout);
end

function C_EditMode.RenameLayout(index, newName)
	Load();

	if layouts[index] and newName and newName ~= "" then
		layouts[index].layoutName = newName;
		Save();
		FireEvent("EDIT_MODE_LAYOUTS_UPDATED", layouts, activeLayout);
	end
end

function C_EditMode.IsValidLayoutName(name)
	return name ~= nil and name ~= "" and #name <= 32;
end

function C_EditMode.GetAccountSettings()
	Load();

	local result = {};
	for setting, value in pairs(accountSettings) do
		result[#result + 1] = { setting = setting, value = value };
	end
	return result;
end

function C_EditMode.SetAccountSetting(setting, value)
	Load();
	accountSettings[setting] = value;
	Save();
end

function C_EditMode.OnEditModeExit()
	Save();
end

-- сохранение при выходе, если что-то не записалось
local saver = CreateFrame("Frame");
saver:RegisterEvent("PLAYER_LOGIN");
saver:RegisterEvent("PLAYER_LOGOUT");
saver:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		Load();
	else
		Save();
	end
end);
