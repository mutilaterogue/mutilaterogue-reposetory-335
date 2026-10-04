-- C_DamageMeter для 3.3.5a: счётчик собирается из боевого лога.
-- В 3.3.5 нет ни C_DamageMeter, ни серверных сессий, поэтому всё считается на клиенте
-- по COMBAT_LOG_EVENT_UNFILTERED и хранится в трёх сессиях: текущий бой, прошлый, общий итог.

C_DamageMeter = C_DamageMeter or {};

Enum = Enum or {};
-- значения строго по DamageMeterConstantsDocumentation
Enum.DamageMeterSessionType = Enum.DamageMeterSessionType or { Overall = 0, Current = 1, Expired = 2 };
Enum.DamageMeterType = Enum.DamageMeterType or {
	DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4,
	Interrupts = 5, Dispels = 6, DamageTaken = 7, AvoidableDamageTaken = 8,
	Deaths = 9, EnemyDamageTaken = 10,
};
Enum.DamageMeterSourceDisplayType = Enum.DamageMeterSourceDisplayType or { None = 0, Ally = 1, Enemy = 2 };
Enum.DamageMeterStorageType = Enum.DamageMeterStorageType or {
	Damage = 0, HealingAndAbsorbs = 1, Absorbs = 2, Interrupts = 3, Dispels = 4,
	DamageTaken = 5, AvoidableDamageTaken = 6, Deaths = 7, EnemyDamageTaken = 8,
};
Enum.DamageMeterSpellDetailsDisplayType = Enum.DamageMeterSpellDetailsDisplayType or {
	SpellCasted = 0, UnitSpecificSpellCasted = 1, SpellAffected = 2, Deaths = 3, EnemyDamageTaken = 4,
};
Enum.DamageMeterCombineSessionType = Enum.DamageMeterCombineSessionType or { None = 0, ChallengeMode = 1, Arena = 2, ArenaMultiRound = 3 };
Enum.DamageMeterStyle = Enum.DamageMeterStyle or { Default = 0, Bordered = 1, Thin = 2, FullBackground = 3 };
Enum.DamageMeterNumbers = Enum.DamageMeterNumbers or { Minimal = 0, Compact = 1, Complete = 2 };
Enum.DamageMeterVisibility = Enum.DamageMeterVisibility or { Always = 0, InCombat = 1, InGroup = 2, Hidden = 3 };

---------------------------------------------------------------------------
-- виртуальные события (клиент 3.3.5 их не знает)
---------------------------------------------------------------------------
local VIRTUAL_EVENTS = {
	DAMAGE_METER_COMBAT_SESSION_UPDATED = true,
	DAMAGE_METER_CURRENT_SESSION_UPDATED = true,
	DAMAGE_METER_RESET = true,
};

local listeners = {};

local function Dispatch(event, ...)
	local set = listeners[event];
	if not set then
		return;
	end
	for frame in pairs(set) do
		local handler = frame:GetScript("OnEvent");
		if handler then
			handler(frame, event, ...);
		end
	end
end

function C_DamageMeter.RegisterFrame(frame, event)
	if not VIRTUAL_EVENTS[event] then
		frame:RegisterEvent(event);
		return;
	end
	listeners[event] = listeners[event] or {};
	listeners[event][frame] = true;
end

function C_DamageMeter.UnregisterFrame(frame, event)
	if listeners[event] then
		listeners[event][frame] = nil;
	end
end

-- бой считается законченным, если урона и лечения не было столько секунд
local COMBAT_TIMEOUT = 5;

---------------------------------------------------------------------------
-- хранилище
---------------------------------------------------------------------------
-- session = { startTime, endTime, sources = { [guid] = source } }
-- source  = { sourceGUID, sourceCreatureID, name, classFilename, isPlayer,
--             amounts = { [damageMeterType] = number },
--             spells  = { [damageMeterType] = { [spellID] = combatSpell } } }
local sessions = {};
local sessionCounter = 0;

local function NewSession()
	sessionCounter = sessionCounter + 1;
	return {
		sessionID = sessionCounter,
		startTime = GetTime(),
		endTime = nil,
		sources = {},
	};
end

local current = NewSession();
local expired = nil;
local overall = NewSession();

local lastActivity = 0;

local function GetSessionByType(sessionType)
	if sessionType == Enum.DamageMeterSessionType.Current then
		return current;
	elseif sessionType == Enum.DamageMeterSessionType.Expired then
		return expired;
	end
	return overall;
end

local function GetSessionByID(sessionID)
	for _, session in pairs({ current, expired, overall }) do
		if session and session.sessionID == sessionID then
			return session;
		end
	end
end

-- id существа из guid (для неигровых источников)
local function GetCreatureID(guid)
	if not guid then
		return nil;
	end
	local id = tonumber(strsub(guid, 9, 12), 16);
	return id;
end

local COMBATLOG_OBJECT_TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400;

local function GetSource(session, guid, name, flags)
	if not guid or not name then
		return nil;
	end

	local source = session.sources[guid];
	if not source then
		source = {
			sourceGUID = guid,
			sourceCreatureID = GetCreatureID(guid),
			name = name,
			isPlayer = flags and bit.band(flags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 or false,
			amounts = {},
			spells = {},
		};

		source.isFriendly = flags and bit.band(flags, COMBATLOG_OBJECT_REACTION_FRIENDLY or 0x10) > 0 or false;
		source.isGroupMember = source.isPlayer and (guid == UnitGUID("player") or UnitInParty(name) or UnitInRaid(name)) and true or false;

		session.sources[guid] = source;
	end

	-- the class: by the GUID (any player seen in the combat log), by name only as a fallback
	if source.isPlayer and not source.classFilename then
		local classFilename;
		if GetPlayerInfoByGUID then
			classFilename = select(2, GetPlayerInfoByGUID(guid));
		end
		if not classFilename then
			classFilename = select(2, UnitClass(guid == UnitGUID("player") and "player" or name));
		end
		source.classFilename = classFilename;
	end

	return source;
end

local function AddAmount(session, guid, name, flags, meterType, amount, spellID, spellName, spellIcon)
	if not amount or amount <= 0 then
		return;
	end

	local source = GetSource(session, guid, name, flags);
	if not source then
		return;
	end

	source.amounts[meterType] = (source.amounts[meterType] or 0) + amount;

	local spells = source.spells[meterType];
	if not spells then
		spells = {};
		source.spells[meterType] = spells;
	end

	local key = spellID or 0;
	local spell = spells[key];
	if not spell then
		spell = {
			spellID = spellID,
			name = spellName or (spellID and GetSpellInfo(spellID)) or MELEE or "Автоатака",
			icon = spellIcon or (spellID and select(3, GetSpellInfo(spellID))) or "Interface\\Icons\\INV_Sword_04",
			totalAmount = 0,
			hitCount = 0,
		};
		spells[key] = spell;
	end

	spell.totalAmount = spell.totalAmount + amount;
	spell.hitCount = spell.hitCount + 1;
end

local function AddCount(session, guid, name, flags, meterType, spellID)
	AddAmount(session, guid, name, flags, meterType, 1, spellID);
end

---------------------------------------------------------------------------
-- разбор боевого лога
---------------------------------------------------------------------------
local DAMAGE_EVENTS = {
	SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true,
	SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true, SPELL_BUILDING_DAMAGE = true,
};

local HEAL_EVENTS = {
	SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true,
};

local function Record(timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...)
	local meterTypes = Enum.DamageMeterType;

	if DAMAGE_EVENTS[event] then
		local spellID, spellName, _, amount;

		if event == "SWING_DAMAGE" then
			amount = ...;
		else
			spellID, spellName, _, amount = ...;
		end

		AddAmount(current, sourceGUID, sourceName, sourceFlags, meterTypes.DamageDone, amount, spellID, spellName);
		AddAmount(overall, sourceGUID, sourceName, sourceFlags, meterTypes.DamageDone, amount, spellID, spellName);

		AddAmount(current, destGUID, destName, destFlags, meterTypes.DamageTaken, amount, spellID, spellName);
		AddAmount(overall, destGUID, destName, destFlags, meterTypes.DamageTaken, amount, spellID, spellName);

		lastActivity = GetTime();
	elseif HEAL_EVENTS[event] then
		local spellID, spellName, _, amount, overhealing = ...;
		local effective = amount - (overhealing or 0);

		AddAmount(current, sourceGUID, sourceName, sourceFlags, meterTypes.HealingDone, effective, spellID, spellName);
		AddAmount(overall, sourceGUID, sourceName, sourceFlags, meterTypes.HealingDone, effective, spellID, spellName);

		lastActivity = GetTime();
	elseif event == "SPELL_INTERRUPT" then
		local spellID, spellName = ...;
		AddCount(current, sourceGUID, sourceName, sourceFlags, meterTypes.Interrupts, spellID);
		AddCount(overall, sourceGUID, sourceName, sourceFlags, meterTypes.Interrupts, spellID);
	elseif event == "SPELL_DISPEL" or event == "SPELL_STOLEN" then
		local spellID = ...;
		AddCount(current, sourceGUID, sourceName, sourceFlags, meterTypes.Dispels, spellID);
		AddCount(overall, sourceGUID, sourceName, sourceFlags, meterTypes.Dispels, spellID);
	elseif event == "UNIT_DIED" or event == "UNIT_DESTROYED" then
		AddCount(current, destGUID, destName, destFlags, meterTypes.Deaths, nil);
		AddCount(overall, destGUID, destName, destFlags, meterTypes.Deaths, nil);
	end
end

---------------------------------------------------------------------------
-- сборка данных для интерфейса
---------------------------------------------------------------------------
local function SessionDuration(session)
	if not session then
		return 0;
	end
	return math.max(1, (session.endTime or GetTime()) - session.startTime);
end

-- нормализуем тип: Dps считается из урона, Hps из лечения
local function ResolveType(damageMeterType)
	if damageMeterType == Enum.DamageMeterType.Dps then
		return Enum.DamageMeterType.DamageDone, true;
	elseif damageMeterType == Enum.DamageMeterType.Hps then
		return Enum.DamageMeterType.HealingDone, true;
	end
	return damageMeterType, false;
end

-- учитывать ли чужих игроков (CVar damageMeterGroupOnly)
local function ShouldIncludeSource(source)
	if GetCVar and GetCVar("damageMeterGroupOnly") == "0" then
		return true;
	end

	if not source.isPlayer then
		return true;		-- мобы и питомцы нужны для "полученного урона"
	end

	return source.isGroupMember;
end

local function BuildSources(session, damageMeterType)
	local baseType, perSecond = ResolveType(damageMeterType);
	local duration = SessionDuration(session);
	local result = {};
	local maxAmount = 0;

	for _, source in pairs(session.sources) do
		local amount = source.amounts[baseType];
		if source.isPlayer and not source.classFilename and GetPlayerInfoByGUID then
			source.classFilename = select(2, GetPlayerInfoByGUID(source.sourceGUID));
		end
		if amount and amount > 0 and ShouldIncludeSource(source) then
			local entry = {
				sourceGUID = source.sourceGUID,
				sourceCreatureID = source.sourceCreatureID,
				name = source.name,
				classFilename = source.classFilename,
				specIconID = 0,
				totalAmount = amount,
				amountPerSecond = amount / duration,
				isLocalPlayer = source.sourceGUID == UnitGUID("player"),
				deathRecapID = 0,
				deathTimeSeconds = 0,
				classification = source.classification or "normal",
				sourceDisplayType = source.isPlayer and Enum.DamageMeterSourceDisplayType.Ally or Enum.DamageMeterSourceDisplayType.Enemy,
				factionGroup = nil,
				showsValuePerSecondAsPrimary = perSecond,
			};
			table.insert(result, entry);
			maxAmount = math.max(maxAmount, amount);
		end
	end

	table.sort(result, function(a, b)
		return a.totalAmount > b.totalAmount;
	end);

	for index, entry in ipairs(result) do
		entry.index = index;
		entry.maxAmount = maxAmount;
	end

	return result, maxAmount;
end

local function BuildSessionInfo(session, damageMeterType)
	if not session then
		return nil;
	end

	local sources, maxAmount = BuildSources(session, damageMeterType);
	local total = 0;
	for _, entry in ipairs(sources) do
		total = total + entry.totalAmount;
	end

	return {
		sessionID = session.sessionID,
		durationSeconds = SessionDuration(session),
		combatSources = sources,
		maxAmount = maxAmount,
		totalAmount = total,
	};
end

---------------------------------------------------------------------------
-- публичный API
---------------------------------------------------------------------------
function C_DamageMeter.IsDamageMeterAvailable()
	return true, "";
end

function C_DamageMeter.GetCombatSessionFromType(sessionType, damageMeterType)
	return BuildSessionInfo(GetSessionByType(sessionType), damageMeterType);
end

function C_DamageMeter.GetCombatSessionFromID(sessionID, damageMeterType)
	return BuildSessionInfo(GetSessionByID(sessionID), damageMeterType);
end

-- разбивка по заклинаниям для одного источника
local function BuildSourceInfo(session, damageMeterType, sourceGUID, sourceCreatureID)
	if not session then
		return nil;
	end

	local source;
	for _, candidate in pairs(session.sources) do
		if (sourceGUID and candidate.sourceGUID == sourceGUID)
			or (sourceCreatureID and candidate.sourceCreatureID == sourceCreatureID) then
			source = candidate;
			break;
		end
	end

	if not source then
		return nil;
	end

	local baseType, perSecond = ResolveType(damageMeterType);
	local duration = SessionDuration(session);
	local spells = {};
	local maxAmount, total = 0, 0;

	for _, spell in pairs(source.spells[baseType] or {}) do
		table.insert(spells, {
			spellID = spell.spellID or 0,
			name = spell.name,
			icon = spell.icon,
			totalAmount = spell.totalAmount,
			amountPerSecond = spell.totalAmount / duration,
			creatureName = source.name,
			overkillAmount = spell.overkillAmount or 0,
			isAvoidable = false,
			isDeadly = false,
			hitCount = spell.hitCount,
			combatSpellDetails = spell.details or {},
		});
		maxAmount = math.max(maxAmount, spell.totalAmount);
		total = total + spell.totalAmount;
	end

	table.sort(spells, function(a, b)
		return a.totalAmount > b.totalAmount;
	end);

	return {
		name = source.name,
		classFilename = source.classFilename,
		combatSpells = spells,
		maxAmount = maxAmount,
		totalAmount = total,
		showsValuePerSecondAsPrimary = perSecond,
	};
end

function C_DamageMeter.GetCombatSessionSourceFromType(sessionType, damageMeterType, sourceGUID, sourceCreatureID)
	return BuildSourceInfo(GetSessionByType(sessionType), damageMeterType, sourceGUID, sourceCreatureID);
end

function C_DamageMeter.GetCombatSessionSourceFromID(sessionID, damageMeterType, sourceGUID, sourceCreatureID)
	return BuildSourceInfo(GetSessionByID(sessionID), damageMeterType, sourceGUID, sourceCreatureID);
end

function C_DamageMeter.GetSessionDurationSeconds(sessionType)
	return SessionDuration(GetSessionByType(sessionType));
end

function C_DamageMeter.GetAvailableCombatSessions()
	local list = {
		{ sessionID = current.sessionID, sessionType = Enum.DamageMeterSessionType.Current,
			name = DAMAGE_METER_CURRENT_SESSION, durationSeconds = SessionDuration(current) },
		{ sessionID = overall.sessionID, sessionType = Enum.DamageMeterSessionType.Overall,
			name = DAMAGE_METER_OVERALL_SESSION, durationSeconds = SessionDuration(overall) },
	};

	if expired then
		table.insert(list, 2, { sessionID = expired.sessionID, sessionType = Enum.DamageMeterSessionType.Expired,
			name = format(DAMAGE_METER_COMBAT_NUMBER, expired.sessionID), durationSeconds = SessionDuration(expired) });
	end

	return list;
end

function C_DamageMeter.ResetAllCombatSessions()
	current = NewSession();
	expired = nil;
	overall = NewSession();

	Dispatch("DAMAGE_METER_RESET");
end

---------------------------------------------------------------------------
-- сохранение между релогами (WriteCustomFile/ReadCustomFile из DLL)
---------------------------------------------------------------------------
local SAVE_FILE = "DamageMeter.txt";

local function SerializeSession(session)
	local parts = {};

	for guid, source in pairs(session.sources) do
		local amounts = {};
		for meterType, amount in pairs(source.amounts) do
			table.insert(amounts, meterType..":"..math.floor(amount));
		end

		if #amounts > 0 then
			table.insert(parts, table.concat({
				guid, source.name, source.classFilename or "",
				source.isPlayer and 1 or 0, source.isGroupMember and 1 or 0,
				table.concat(amounts, ","),
			}, "|"));
		end
	end

	return math.floor(session.startTime).."~"..math.floor(session.endTime or GetTime()).."~"..table.concat(parts, ";");
end

local function DeserializeSession(text)
	local session = NewSession();
	if not text or text == "" then
		return session;
	end

	local startTime, endTime, body = strsplit("~", text);
	local duration = (tonumber(endTime) or 0) - (tonumber(startTime) or 0);

	-- время храним длительностью: GetTime после релога начинается заново
	session.startTime = GetTime() - math.max(1, duration);
	session.endTime = GetTime();

	for _, entry in ipairs({ strsplit(";", body or "") }) do
		if entry ~= "" then
			local guid, name, class, isPlayer, isGroup, amounts = strsplit("|", entry);

			local source = {
				sourceGUID = guid,
				sourceCreatureID = GetCreatureID(guid),
				name = name,
				classFilename = class ~= "" and class or nil,
				isPlayer = isPlayer == "1",
				isGroupMember = isGroup == "1",
				amounts = {},
				spells = {},
			};

			for _, pair in ipairs({ strsplit(",", amounts or "") }) do
				local meterType, amount = strsplit(":", pair);
				if meterType and amount then
					source.amounts[tonumber(meterType)] = tonumber(amount);
				end
			end

			session.sources[guid] = source;
		end
	end

	return session;
end

function C_DamageMeter.SaveSessions()
	if not WriteCustomFile then
		return;
	end
	pcall(WriteCustomFile, SAVE_FILE, SerializeSession(overall));
end

function C_DamageMeter.LoadSessions()
	if not ReadCustomFile then
		return;
	end

	-- файла может не быть: тогда ReadCustomFile бросает ошибку
	local ok, text = pcall(ReadCustomFile, SAVE_FILE);
	if not ok then
		return;
	end

	if text and text ~= "" then
		overall = DeserializeSession(text);
	end
end

-- отладка: сколько источников набрано до фильтра
function C_DamageMeter.Debug()
	local count, total = 0, 0;

	for guid, source in pairs(current.sources) do
		count = count + 1;
		print(guid, source.name, "player:", tostring(source.isPlayer), "group:", tostring(source.isGroupMember),
			"dmg:", source.amounts[Enum.DamageMeterType.DamageDone] or 0);
		total = total + (source.amounts[Enum.DamageMeterType.DamageDone] or 0);
	end

	print("sources:", count, "total:", total, "playerGUID:", UnitGUID("player"));
end

---------------------------------------------------------------------------
-- события
---------------------------------------------------------------------------
local driver = CreateFrame("Frame");
driver:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
driver:RegisterEvent("PLAYER_REGEN_DISABLED");
driver:RegisterEvent("PLAYER_REGEN_ENABLED");
-- авто-сброс при входе в новое подземелье, рейд, поле боя или арену
driver:RegisterEvent("PLAYER_ENTERING_WORLD");
driver:RegisterEvent("PLAYER_LOGOUT");

driver:SetScript("OnEvent", function(self, event, ...)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		Record(...);
		-- интерфейс обновляем не чаще раза в кадр
		self.dirty = true;
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- новый бой: текущая сессия уходит в "прошлый бой"
		if next(current.sources) then
			current.endTime = GetTime();
			expired = current;
		end
		current = NewSession();
		lastActivity = GetTime();
	elseif event == "PLAYER_REGEN_ENABLED" then
		current.endTime = GetTime();
	elseif event == "PLAYER_LOGOUT" then
		C_DamageMeter.SaveSessions();
	elseif event == "PLAYER_ENTERING_WORLD" then
		if not self.loaded then
			self.loaded = true;
			C_DamageMeter.LoadSessions();
		end

		local inInstance, instanceType = IsInInstance();
		local instanceKey = inInstance and (instanceType..(GetInstanceInfo and select(8, GetInstanceInfo()) or "")) or nil;

		if instanceKey and instanceKey ~= self.lastInstanceKey and GetCVar("damageMeterAutoReset") ~= "0" then
			C_DamageMeter.ResetAllCombatSessions();
		end

		self.lastInstanceKey = instanceKey;
	end
end);

-- бой мог кончиться без выхода из боя (например, у неигровых источников)
driver:SetScript("OnUpdate", function(self)
	if self.dirty then
		self.dirty = nil;
		Dispatch("DAMAGE_METER_CURRENT_SESSION_UPDATED");
		Dispatch("DAMAGE_METER_COMBAT_SESSION_UPDATED", Enum.DamageMeterType.DamageDone, current.sessionID);
	end

	if current.endTime or not next(current.sources) then
		return;
	end
	if GetTime() - lastActivity > COMBAT_TIMEOUT then
		current.endTime = lastActivity;
	end
end);
