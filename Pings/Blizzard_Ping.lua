-- Group pings (retail PingSystem) for 3.3.5. Server: server/mythic_plus.cpp (HandlePing / UpdatePings).
-- Hold the PINGWHEEL key: the wheel opens at the cursor, release over a sector to ping (a short tap pings
-- by the target: an enemy - attack, else - warning). The ping goes to the target, or to your position.
-- Receivers: a marker on a circle around the screen center pointing to the ping, its distance, the chat line.
--   C->S "PING" : type : target guid     S->C "PING" : id : type : sender : target : dx : dy / "PING_POS" : id : dx : dy

-- global string or its key, so a missing string never breaks the text
local function S(key)
	return _G[key] or key;
end

BINDING_HEADER_PINGSYSTEM = BINDING_HEADER_PINGSYSTEM or S("PING_SYSTEM_LABEL");
BINDING_NAME_PINGWHEEL = BINDING_NAME_PINGWHEEL or S("PING_TYPE_CONTEXTUAL");

PING_ATTACK, PING_WARNING, PING_ON_MY_WAY, PING_ASSIST = 1, 2, 3, 4;

local PING_INFO = {
	[PING_ATTACK]    = { name = "PING_TYPE_ATTACK",    atlas = "Ping_Marker_Icon_Attack",   r = 1.00, g = 0.25, b = 0.20, sound = "RaidWarning" },
	[PING_WARNING]   = { name = "PING_TYPE_WARNING",   atlas = "Ping_Marker_Icon_Warning",  r = 1.00, g = 0.82, b = 0.00, sound = "RaidWarning" },
	[PING_ON_MY_WAY] = { name = "PING_TYPE_ON_MY_WAY", atlas = "Ping_Marker_Icon_OnMyWay",  r = 0.30, g = 0.80, b = 1.00, sound = "MapPing" },
	[PING_ASSIST]    = { name = "PING_TYPE_ASSIST",    atlas = "Ping_Marker_Icon_Assist",   r = 0.30, g = 1.00, b = 0.30, sound = "MapPing" },
};

-- wheel sectors: top, right, bottom, left
local WHEEL = { PING_ATTACK, PING_WARNING, PING_ON_MY_WAY, PING_ASSIST };
local WHEEL_RADIUS = 58;
local MARKER_RADIUS = 170;
local PING_TIME = 5;

function Ping_Send(pingType)
	local guid = UnitExists("target") and UnitGUID("target") or "0";
	MythicPlus_Send("PING", pingType, (guid:gsub("^0x", "")));
end

local function ContextualType()
	if UnitExists("target") and UnitCanAttack("player", "target") then
		return PING_ATTACK;
	end
	return PING_WARNING;
end

---------------------------------------------------------------------------
-- wheel
---------------------------------------------------------------------------
local function CursorOffset(frame)
	local x, y = GetCursorPosition();
	local scale = frame:GetEffectiveScale();
	local cx, cy = frame:GetCenter();
	return x / scale - cx, y / scale - cy;
end

local function WheelSector(frame)
	local x, y = CursorOffset(frame);
	if x * x + y * y < 20 * 20 then
		return nil;
	end
	-- 0 top, 1 right, 2 bottom, 3 left
	local angle = math.atan2(x, y);
	local sector = math.floor((angle + math.pi / 4) / (math.pi / 2)) % 4;
	return sector + 1;
end

function PingWheel_OnLoad(self)
	self.buttons = {};
	local offsets = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } };
	for i, pingType in ipairs(WHEEL) do
		local info = PING_INFO[pingType];
		local button = CreateFrame("Frame", nil, self, "PingWheelButtonTemplate");
		button:SetPoint("CENTER", self, "CENTER", offsets[i][1] * WHEEL_RADIUS, offsets[i][2] * WHEEL_RADIUS);
		button.Icon:SetAtlas(info.atlas);
		button.Label:SetText(S(info.name));
		button.Label:SetTextColor(info.r, info.g, info.b);
		self.buttons[i] = button;
	end
end

function PingWheel_OnUpdate(self)
	local sector = WheelSector(self);
	for i, button in ipairs(self.buttons) do
		button.Highlight:SetShown(i == sector);
		button:SetScale(i == sector and 1.15 or 1);
	end
end

function PingWheel_Show()
	local wheel = PingWheelFrame;
	local x, y = GetCursorPosition();
	local scale = UIParent:GetEffectiveScale();
	wheel:ClearAllPoints();
	wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale);
	wheel:Show();
end

function PingWheel_Release()
	local wheel = PingWheelFrame;
	if not wheel:IsShown() then
		return;
	end
	local sector = WheelSector(wheel);
	wheel:Hide();
	Ping_Send(sector and WHEEL[sector] or ContextualType());
end

SLASH_PING1 = "/ping";
SlashCmdList["PING"] = function(msg)
	msg = strlower(msg or "");
	local types = { attack = PING_ATTACK, warning = PING_WARNING, onmyway = PING_ON_MY_WAY, assist = PING_ASSIST };
	Ping_Send(types[msg] or ContextualType());
end

---------------------------------------------------------------------------
-- markers of received pings
---------------------------------------------------------------------------
local markers = {};		-- [id] = frame
local pool = {};

local function PlaceMarker(marker)
	local dx, dy = marker.dx, marker.dy;
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
	Comm_Register("PING", function(id, pingType, sender, target, dx, dy)
		id = tonumber(id);
		local info = PING_INFO[tonumber(pingType) or 0];
		if not id or not info then
			return;
		end
		local marker = markers[id] or AcquireMarker();
		markers[id] = marker;
		marker.id = id;
		marker.dx = tonumber(dx) or 0;
		marker.dy = tonumber(dy) or 0;
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
		DEFAULT_CHAT_FRAME:AddMessage(text, info.r, info.g, info.b);
		PlaySound(info.sound);
	end);

	Comm_Register("PING_POS", function(id, dx, dy)
		local marker = markers[tonumber(id) or 0];
		if marker then
			marker.dx = tonumber(dx) or marker.dx;
			marker.dy = tonumber(dy) or marker.dy;
		end
	end);
end
