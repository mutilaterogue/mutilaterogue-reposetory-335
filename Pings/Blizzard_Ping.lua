-- Group pings (retail PingSystem) for 3.3.5. Server: server/mythic_plus.cpp (HandlePing / UpdatePings).
-- Hold the TOGGLEPINGLISTENER key: the wheel opens at the cursor, release over a sector to ping (a short tap pings
-- by the target: an enemy - attack, else - warning). The ping goes to the target, or to your position.
-- Receivers: a marker on a circle around the screen center pointing to the ping, its distance, the chat line.
--   C->S "PING" : type : target guid     S->C "PING" : id : type : sender : target : dx : dy / "PING_POS" : id : dx : dy

-- global string or its key, so a missing string never breaks the text
local function S(key)
	return _G[key] or key;
end


PING_ATTACK, PING_WARNING, PING_ON_MY_WAY, PING_ASSIST = 1, 2, 3, 4;

local PING_INFO = {
	[PING_ATTACK]    = { name = "PING_TYPE_ATTACK",    atlas = "Ping_Marker_Icon_Attack",   r = 1.00, g = 0.25, b = 0.20, sound = "RaidWarning" },
	[PING_WARNING]   = { name = "PING_TYPE_WARNING",   atlas = "Ping_Marker_Icon_Warning",  r = 1.00, g = 0.82, b = 0.00, sound = "RaidWarning" },
	[PING_ON_MY_WAY] = { name = "PING_TYPE_ON_MY_WAY", atlas = "Ping_Marker_Icon_OnMyWay",  r = 0.30, g = 0.80, b = 1.00, sound = "MapPing" },
	[PING_ASSIST]    = { name = "PING_TYPE_ASSIST",    atlas = "Ping_Marker_Icon_Assist",   r = 0.30, g = 1.00, b = 0.30, sound = "MapPing" },
};

-- wheel sectors: top, right, bottom, left
local WHEEL = { PING_ATTACK, PING_WARNING, PING_ON_MY_WAY, PING_ASSIST };
local MARKER_RADIUS = 170;
local PING_TIME = 5;

-- the world point under the cursor (CameraTraceLine of the client dll): x, y, z or nil
function Ping_CursorWorldPosition()
	if not CameraTraceLine or not WorldToCamera then
		return nil;
	end
	local _, _, _, fov = WorldToCamera(0, 0, 0);
	if not fov then
		return nil;
	end
	local x, y = GetCursorPosition();
	local scale = UIParent:GetEffectiveScale();
	local width, height = UIParent:GetWidth(), UIParent:GetHeight();
	local sx, sy = x / scale / width, y / scale / height;
	local tanV = math.tan(fov * PING_FOV_FACTOR / 2);
	local tanH = tanV * width / height;
	return CameraTraceLine((sx * 2 - 1) * tanH, (sy * 2 - 1) * tanV, 1, 200);
end

-- point: { x, y, z } under the cursor when the ping was started; the cursor over the target pings the target
function Ping_Send(pingType, point)
	if UnitExists("mouseover") and UnitIsUnit("mouseover", "target") then
		MythicPlus_Send("PING", pingType, "T");
	elseif point then
		MythicPlus_Send("PING", pingType, "P", math.floor(point[1] * 10), math.floor(point[2] * 10), math.floor(point[3] * 10));
	elseif UnitExists("target") then
		MythicPlus_Send("PING", pingType, "T");
	else
		MythicPlus_Send("PING", pingType, "0");
	end
end

local function CursorPoint()
	local x, y, z = Ping_CursorWorldPosition();
	return x and { x, y, z } or nil;
end

-- the key bindings PINGATTACK / PINGWARNING / PINGONMYWAY / PINGASSIST (Bindings.xml)
function Ping_SendAtCursor(pingType)
	Ping_Send(pingType, CursorPoint());
end

local function ContextualType()
	if UnitExists("target") and UnitCanAttack("player", "target") then
		return PING_ATTACK;
	end
	return PING_WARNING;
end

---------------------------------------------------------------------------
-- wheel (retail RadialWheel, Blizzard_RadialWheel.lua): hold - choose, release - ping; a short tap - by the target
---------------------------------------------------------------------------
local WHEEL_ICONS = {
	[PING_ATTACK]    = "Ping_Wheel_Icon_Attack",
	[PING_WARNING]   = "Ping_Wheel_Icon_Warning",
	[PING_ON_MY_WAY] = "Ping_Wheel_Icon_OnMyWay",
	[PING_ASSIST]    = "Ping_Wheel_Icon_Assist",
};
local TAP_TIME = 0.2;

function PingWheel_OnLoad(self)
	Mixin(self, RadialWheelFrameMixin);
	self:OnLoad();
end

-- pingMode "1": a press opens the wheel, the next press pings (retail "toggle"); "0": hold and release
local function ToggleMode()
	return GetCVar("pingMode") == "1";
end

function PingWheel_Show()
	local wheel = PingWheelFrame;
	if ToggleMode() and wheel:IsShown() and not wheel.isWheelClosing then
		PingWheel_Release(true);
		return;
	end
	local x, y = GetCursorPosition();
	local scale = UIParent:GetEffectiveScale();
	wheel:ClearAllPoints();
	wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale);
	local wedges = {};
	for _, pingType in ipairs(WHEEL) do
		table.insert(wedges, { type = pingType, icon = WHEEL_ICONS[pingType], text = S(PING_INFO[pingType].name) });
	end
	wheel.pressedAt = GetTime();
	wheel.point = CursorPoint();
	wheel:SelectionStart(wedges, false);
end

function PingWheel_Release(force)
	local wheel = PingWheelFrame;
	if ToggleMode() and not force then
		return;
	end
	if not wheel:IsShown() or wheel.isWheelClosing then
		return;
	end
	local selected = wheel:SelectionEnd();
	local tap = GetTime() - (wheel.pressedAt or 0) < TAP_TIME;
	wheel:AnimateOutro();
	if selected then
		Ping_Send(selected.type, wheel.point);
	elseif tap then
		Ping_Send(ContextualType(), wheel.point);
	end
end

-- /ping [@unit] type (retail macro): /ping attack, /ping [@target] warning; the unit - its ping (the target)
SLASH_PING1 = "/ping";
SLASH_PING2 = "/отметка";
local PING_TYPE_NAMES = {
	attack = PING_ATTACK, warning = PING_WARNING, onmyway = PING_ON_MY_WAY, assist = PING_ASSIST,
	["атака"] = PING_ATTACK, ["внимание"] = PING_WARNING, ["иду"] = PING_ON_MY_WAY, ["помощь"] = PING_ASSIST,
};
SlashCmdList["PING"] = function(msg)
	msg = strlower(msg or "");
	local unit = msg:match("%[@([^%]]+)%]");
	msg = strtrim(msg:gsub("%[[^%]]*%]", ""));
	local pingType = PING_TYPE_NAMES[msg] or ContextualType();
	if unit then
		-- the server pings the selection: only the target (or a unit that is the target)
		if UnitExists(unit) and UnitIsUnit(unit, "target") then
			MythicPlus_Send("PING", pingType, "T");
		end
		return;
	end
	Ping_Send(pingType, CursorPoint());
end

---------------------------------------------------------------------------
-- markers of received pings
---------------------------------------------------------------------------
local markers = {};		-- [id] = frame
local pool = {};

-- world point -> UIParent coordinates (WorldToCamera of the client dll, dll\WorldToScreen); nil when it is behind
-- the camera or the dll has no such function. Tuning: the vertical field of view = camera fov * PING_FOV_FACTOR
-- (3.3.5: about 35 degrees per radian of the camera fov).
PING_FOV_FACTOR = 0.5;

function Ping_WorldToScreen(x, y, z)
	if not WorldToCamera then
		return nil;
	end
	local right, up, forward, fov = WorldToCamera(x, y, z);
	if not right or forward <= 0.5 then
		return nil;
	end
	local width, height = UIParent:GetWidth(), UIParent:GetHeight();
	local tanV = math.tan(fov * PING_FOV_FACTOR / 2);
	local tanH = tanV * width / height;
	local sx = (right / (forward * tanH)) * 0.5 + 0.5;
	local sy = (up / (forward * tanV)) * 0.5 + 0.5;
	if sx < 0 or sx > 1 or sy < 0 or sy > 1 then
		return nil;
	end
	return sx * width, sy * height;
end

local function PlaceMarker(marker)
	local dx, dy = marker.dx, marker.dy;
	-- in the world: over the point itself
	if marker.wx then
		local sx, sy = Ping_WorldToScreen(marker.wx, marker.wy, marker.wz);
		if sx then
			marker:ClearAllPoints();
			marker:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", sx, sy);
			marker.Distance:SetFormattedText("%d", math.floor(math.sqrt(dx * dx + dy * dy) + 0.5));
			return;
		end
	end
	-- off screen / no dll: on the circle around the center, towards the point
	local facing = GetPlayerFacing() or 0;
	-- world: x north, y west; facing 0 = north, counter-clockwise
	local rel = math.atan2(dy, dx) - facing;
	marker:ClearAllPoints();
	marker:SetPoint("CENTER", UIParent, "CENTER", -math.sin(rel) * MARKER_RADIUS, math.cos(rel) * MARKER_RADIUS);
	marker.Distance:SetFormattedText("%d", math.floor(math.sqrt(dx * dx + dy * dy) + 0.5));
end

local function AcquireMarker()
	local marker = table.remove(pool);
	if not marker then
		marker = CreateFrame("Frame", nil, UIParent, "PingMarkerTemplate");
	end
	return marker;
end

function PingMarker_OnUpdate(self, elapsed)
	self.timeLeft = self.timeLeft - elapsed;
	if self.timeLeft <= 0 then
		self:Hide();
		markers[self.id] = nil;
		table.insert(pool, self);
		return;
	end
	-- in 0.2 s, out in the last 0.5 s, the icon pulses
	local shown = PING_TIME - self.timeLeft;
	local alpha = math.min(1, shown / 0.2, self.timeLeft / 0.5);
	self:SetAlpha(alpha);
	local size = 36 * (1 + 0.15 * math.abs(math.sin(shown * 4)));
	self.Icon:SetWidth(size);
	self.Icon:SetHeight(size);
	PlaceMarker(self);
end

if Comm_Register then
	Comm_Register("PING", function(id, pingType, sender, target, dx, dy, wx, wy, wz)
		id = tonumber(id);
		local info = PING_INFO[tonumber(pingType) or 0];
		if not id or not info then
			return;
		end
		if Ping_IsOptionOn and not Ping_IsOptionOn("pingEnabled") then
			return;
		end
		local marker = markers[id] or AcquireMarker();
		markers[id] = marker;
		marker.id = id;
		marker.dx = tonumber(dx) or 0;
		marker.dy = tonumber(dy) or 0;
		marker.wx = wx and tonumber(wx) and tonumber(wx) / 10;
		marker.wy = wy and tonumber(wy) and tonumber(wy) / 10;
		marker.wz = wz and tonumber(wz) and tonumber(wz) / 10;
		marker.timeLeft = PING_TIME;
		marker.Icon:SetAtlas(info.atlas);
		marker.Name:SetText(sender or "");
		marker.Name:SetTextColor(info.r, info.g, info.b);
		marker:Show();
		PlaceMarker(marker);

		local text = (sender or "") .. ": " .. S(info.name);
		if target and target ~= "" then
			text = text .. " - " .. target;
		end
		if not Ping_IsOptionOn or Ping_IsOptionOn("pingChat") then
			DEFAULT_CHAT_FRAME:AddMessage(text, info.r, info.g, info.b);
		end
		if not Ping_IsOptionOn or Ping_IsOptionOn("pingSound") then
			PlaySound(info.sound);
		end
	end);

	Comm_Register("PING_POS", function(id, dx, dy, wx, wy, wz)
		local marker = markers[tonumber(id) or 0];
		if marker then
			marker.dx = tonumber(dx) or marker.dx;
			marker.dy = tonumber(dy) or marker.dy;
			if tonumber(wx) then
				marker.wx, marker.wy, marker.wz = tonumber(wx) / 10, tonumber(wy) / 10, tonumber(wz) / 10;
			end
		end
	end);
end
