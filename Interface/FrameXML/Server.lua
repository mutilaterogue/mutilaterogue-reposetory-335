-- ============================================================
--  Comm.lua — транспорт клиент <-> сервер через аддон-сообщения
--  WoW 3.3.5a / Lua 5.1
-- ============================================================

COMM_PREFIX    = "CIRCLE";
COMM_SEP       = ":";
COMM_MAXBYTES  = 240;
COMM_MAXCHUNKS = 64;

-- Опкод - число (старые, ниже) или имя-строка ("TOYS_LIST").
-- Новые модули используют имена прямо в своём Lua и на сервере: сюда их добавлять не нужно.
CMSG = {   -- клиент -> сервер
	REQUEST_TALENT_TREE			= 1,
    REQUEST_CREATURE_CACHE      = 2,
    REQUEST_HEIRLOOMS           = 3,
    CREATE_HEIRLOOM             = 4,
    REQUEST_CREATURE_BY_DISPLAY = 5,
};

SMSG = {   -- сервер -> клиент
	TALENT_TREE					= 1,
    MASTERY_SPELL               = 2,
    HEIRLOOM_ADDED              = 3,
    HEIRLOOM_LIST               = 4,
    CREATURE_BY_DISPLAY         = 5,
};

local handlers   = {};
local recvBuffer = {};
local loginQueue = {};
local loggedIn   = false;

if not tostringall then
	function tostringall(...)
		local n = select("#", ...);
		local out = {};
		for i = 1, n do out[i] = tostring((select(i, ...))); end
		return unpack(out, 1, n);
	end
end

-- ------------------------------------------------------------
--  Транспорт
-- ------------------------------------------------------------
function SendServerMessage(prefix, ...)
	if select("#", ...) > 1 then
		SendAddonMessage(prefix, strjoin(COMM_SEP, tostringall(...)), "WHISPER", UnitName("player"))
	else
		SendAddonMessage(prefix, ..., "WHISPER", UnitName("player"))
	end
end

-- ------------------------------------------------------------
--  Утилиты
-- ------------------------------------------------------------
local function Normalize(...)
	local n = select("#", ...);
	if n == 0 then return; end

	local out = {};
	for i = 1, n do
		local v = select(i, ...);
		if v == nil then
			out[i] = "";
		elseif type(v) == "boolean" then
			out[i] = v and "1" or "0";
		else
			out[i] = tostring(v);
		end
	end
	return unpack(out, 1, n);
end

-- ------------------------------------------------------------
--  Отправка
-- ------------------------------------------------------------
-- Все аргументы собираются в одну строку через COMM_SEP. Раньше аргументы раскладывались
-- в a1..a8: при одном аргументе a2..a8 были nil, и MeasureLength падал на strlen(nil).
function Comm_Send(opcode, ...)
	if not opcode then return; end

	opcode = tostring(opcode);

	if select("#", ...) == 0 then
		SendServerMessage(COMM_PREFIX, opcode);
		return;
	end

	local body = strjoin(COMM_SEP, Normalize(...));

	if strlen(opcode) + 1 + strlen(body) <= COMM_MAXBYTES then
		SendServerMessage(COMM_PREFIX, opcode .. COMM_SEP .. body);
		return;
	end

	Comm_SendChunked(opcode, body);
end

function Comm_SendChunked(opcode, body)
	local chunkSize = COMM_MAXBYTES - 24;
	local total     = ceil(strlen(body) / chunkSize);

	if total > COMM_MAXCHUNKS then
		DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Comm:|r payload too large, dropped (opcode " .. tostring(opcode) .. ")");
		return;
	end

	for i = 1, total do
		local part = strsub(body, (i - 1) * chunkSize + 1, i * chunkSize);
		SendServerMessage(COMM_PREFIX, "C", opcode, i, total, part);
	end
end

-- ------------------------------------------------------------
--  Регистрация обработчиков
-- ------------------------------------------------------------
function Comm_Register(opcode, func)
	if not opcode or type(func) ~= "function" then return; end

	if not handlers[opcode] then
		handlers[opcode] = {};
	end
	local list = handlers[opcode];
	tinsert(list, func);

	return {
		Unregister = function()
			for i = 1, getn(list) do
				if list[i] == func then
					tremove(list, i);
					return;
				end
			end
		end,
	};
end

function Comm_Unregister(opcode)
	handlers[opcode] = nil;
end

function Comm_OnLogin(callback)
	if loggedIn then
		callback();
		return;
	end
	tinsert(loginQueue, callback);
end

-- ------------------------------------------------------------
--  Приём
-- ------------------------------------------------------------
local function Dispatch(opcode, ...)
	local list = handlers[opcode];
	if not list then return; end

	local snapshot = {};
	for i = 1, getn(list) do
		snapshot[i] = list[i];
	end
	for i = 1, getn(snapshot) do
		snapshot[i](...);
	end
end

local frame = CreateFrame("Frame", "CommFrame");
frame:RegisterEvent("CHAT_MSG_ADDON");
frame:RegisterEvent("PLAYER_ENTERING_WORLD");
frame:RegisterEvent("PLAYER_LEAVING_WORLD");

frame:SetScript("OnEvent", function()
	if event == "PLAYER_ENTERING_WORLD" then
		if not loggedIn then
			loggedIn = true;
			for i = 1, getn(loginQueue) do
				loginQueue[i]();
			end
			loginQueue = {};
		end
		return;

	elseif event == "PLAYER_LEAVING_WORLD" then
		recvBuffer = {};
		return;

	elseif event ~= "CHAT_MSG_ADDON" then
		return;
	end

	if arg1 ~= COMM_PREFIX then return; end
	if arg4 ~= UnitName("player") then return; end
	if not arg2 or arg2 == "" then return; end

	local p1, p2, p3, p4, p5 = strsplit(COMM_SEP, arg2, 5);

	if p1 == "C" then
		local opcode = tonumber(p2) or p2;
		local idx    = tonumber(p3);
		local total  = tonumber(p4);

		if not opcode or not idx or not total then return; end
		if total < 1 or total > COMM_MAXCHUNKS then return; end
		if idx < 1 or idx > total then return; end

		local buf = recvBuffer[opcode];
		if not buf or buf.total ~= total then
			buf = { total = total, received = 0, parts = {} };
			recvBuffer[opcode] = buf;
		end

		if buf.parts[idx] == nil then
			buf.received = buf.received + 1;
		end
		buf.parts[idx] = p5 or "";

		if buf.received < total then return; end

		local full = table.concat(buf.parts, "", 1, total);
		recvBuffer[opcode] = nil;

		Dispatch(opcode, strsplit(COMM_SEP, full));
		return;
	end

	local opcode = tonumber(p1) or p1;
	if not opcode or opcode == "" then return; end
	if not handlers[opcode] then return; end

	local body = strsub(arg2, strlen(p1) + 2);
	if body == "" then
		Dispatch(opcode);
	else
		Dispatch(opcode, strsplit(COMM_SEP, body));
	end
end);

-- ============================================================
--  GetPrimaryTalentTree
-- ============================================================

local primaryTalentTree = {};   -- [spec 0..1] = tree

-- Сервер шлёт: spec : tree : activeSpec
Comm_Register(SMSG.TALENT_TREE, function(spec, tree, activeSpec)
	spec = tonumber(spec);
	tree = tonumber(tree);
	if not spec then return; end

	primaryTalentTree[spec] = tree;

	if activeSpec then
		primaryTalentTree.active = tonumber(activeSpec);
	end

	if PaperDollFrame and PaperDollFrame:IsShown() then
		PaperDollFrame_UpdateStats();
	end
end);

-- Совместимо с ретейловской сигнатурой: без аргумента — активный спек
function GetPrimaryTalentTree(spec)
	if spec == nil then
		spec = primaryTalentTree.active;
		if spec == nil and GetActiveTalentGroup then
			spec = GetActiveTalentGroup() - 1;   -- 3.3.5 отдаёт 1..2
		end
	end
	if spec == nil then return nil; end

	local tree = primaryTalentTree[spec];
	if tree == nil or tree == 0 then
		return nil;
	end
	return tree;
end

function RequestPrimaryTalentTree()
	Comm_Send(CMSG.REQUEST_TALENT_TREE);
end

Comm_OnLogin(RequestPrimaryTalentTree);

-- Обновляем при смене спека и после переучивания талантов
local talentWatcher = CreateFrame("Frame");
talentWatcher:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
talentWatcher:RegisterEvent("CHARACTER_POINTS_CHANGED");
talentWatcher:SetScript("OnEvent", function()
	RequestPrimaryTalentTree();
end);

-- ============================================================
--  Mastery spells
-- ============================================================

SMSG.MASTERY_SPELL = 2;

local masterySpells = {};   -- [tree] = { spell1, spell2 }

Comm_Register(SMSG.MASTERY_SPELL, function(tree, spell1, spell2)
	tree   = tonumber(tree);
	spell1 = tonumber(spell1) or 0;

	if not tree then return; end

	if spell1 == 0 then
		masterySpells[tree] = nil;
		return;
	end

	masterySpells[tree] = { spell1, tonumber(spell2) or 0 };
end);

function GetTalentTreeMasterySpells(tree)
	local data = masterySpells[tree];
	if not data then return nil; end

	if data[2] == 0 then
		return data[1];
	end
	return data[1], data[2];
end