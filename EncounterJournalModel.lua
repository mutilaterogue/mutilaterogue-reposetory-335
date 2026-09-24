-- Boss models for the encounter journal.
--
-- The journal data only knows the display ID of a creature. model:SetModel(path) draws the
-- bare .m2 without the creature textures (white / wrong skin), so the model is shown the same
-- way as uncollected mounts in the collections: through SetCreature(entry) and the creature cache.
--
-- 1. the client asks the server for a creature entry by display ID
--    (AddonComm CMSG.REQUEST_CREATURE_BY_DISPLAY, "displayID,displayID,...")
-- 2. the server finds creature_template with that model, sends SMSG_CREATURE_QUERY_RESPONSE
--    (puts it into creaturecache.wdb) and answers SMSG.CREATURE_BY_DISPLAY "displayID/entry,..."
-- 3. the model is set with SetCreature(entry)

local displayToEntry = {};   -- [displayID] = creature entry (0 = server has no such creature)
local requested = {};        -- [displayID] = true, requested this session
local pendingModels = {};    -- [model] = displayID waiting for the answer

local REAPPLY_DELAY = 1;

local function ApplyEntry(model, entry)
	model:ClearModel();
	model:SetCreature(entry);
	model:SetFacing(MODELFRAME_DEFAULT_ROTATION or 0);

	-- the creature data arrives right after the answer: set it once more a moment later
	model.ejReapplyEntry = entry;
	model.ejReapplyElapsed = 0;
	if not model.ejReapplyHooked then
		model.ejReapplyHooked = true;
		model:HookScript("OnUpdate", function(self, elapsed)
			if not self.ejReapplyEntry then
				return;
			end
			self.ejReapplyElapsed = self.ejReapplyElapsed + elapsed;
			if self.ejReapplyElapsed >= REAPPLY_DELAY then
				self:SetCreature(self.ejReapplyEntry);
				self:SetFacing(MODELFRAME_DEFAULT_ROTATION or 0);
				self.ejReapplyEntry = nil;
			end
		end);
	end
end

-- fallback: bare model by path (old behaviour) when the server can't help
local function ApplyPath(model, displayID)
	local path, scale, height = GetCreatureModelByDisplayID and GetCreatureModelByDisplayID(displayID);
	if not path then
		model:ClearModel();
		return;
	end
	scale = (scale and scale > 0) and scale or 1;
	height = (height and height > 0) and height or 2;
	local effective = height * scale;
	model:SetModel(path);
	model:SetFacing(MODELFRAME_DEFAULT_ROTATION or 0);
	model:SetModelScale(scale);
	model:SetPosition(-0.5 - effective * 0.45, 0, -effective * 0.35);
end

function EncounterJournal_SetModelByDisplayID(model, displayID)
	pendingModels[model] = nil;
	model.ejReapplyEntry = nil;

	local entry = displayToEntry[displayID];
	if entry and entry > 0 then
		ApplyEntry(model, entry);
		return;
	end
	if entry == 0 or not (Comm_Send and CMSG and CMSG.REQUEST_CREATURE_BY_DISPLAY) then
		ApplyPath(model, displayID);
		return;
	end

	model:ClearModel();
	pendingModels[model] = displayID;
	if not requested[displayID] then
		requested[displayID] = true;
		Comm_Send(CMSG.REQUEST_CREATURE_BY_DISPLAY, tostring(displayID));
	end
end

-- warm up: ask for every creature of an encounter at once
function EncounterJournal_PrefetchDisplayIDs(displayIDs)
	if not (Comm_Send and CMSG and CMSG.REQUEST_CREATURE_BY_DISPLAY) then
		return;
	end
	local ids = {};
	for _, displayID in ipairs(displayIDs) do
		if displayID and displayID > 0 and not requested[displayID] and not displayToEntry[displayID] then
			requested[displayID] = true;
			table.insert(ids, tostring(displayID));
		end
	end
	if #ids > 0 then
		Comm_Send(CMSG.REQUEST_CREATURE_BY_DISPLAY, table.concat(ids, ","));
	end
end

if Comm_Register and SMSG and SMSG.CREATURE_BY_DISPLAY then
	Comm_Register(SMSG.CREATURE_BY_DISPLAY, function(text)
		for displayID, entry in (text or ""):gmatch("(%d+)/(%d+)") do
			displayToEntry[tonumber(displayID)] = tonumber(entry);
		end
		for model, displayID in pairs(pendingModels) do
			local entry = displayToEntry[displayID];
			if entry then
				pendingModels[model] = nil;
				if entry > 0 then
					ApplyEntry(model, entry);
				else
					ApplyPath(model, displayID);
				end
			end
		end
	end);
end
