-- TableBuilder (TWW) -> 3.3.5a: недостающие утилиты. Грузится первым.
-- Всё под guard'ами: свои реализации не перезаписываются.

TableIsEmpty = TableIsEmpty or function(tbl)
	return next(tbl) == nil;
end

Sign = Sign or function(value)
	if value > 0 then
		return 1;
	elseif value < 0 then
		return -1;
	end
	return 0;
end

-- в 3.3.5 нет strcmputf8i; сравниваем без учёта регистра (кириллица сравнивается побайтово)
strcmputf8i = strcmputf8i or function(lhs, rhs)
	lhs, rhs = strlower(lhs or ""), strlower(rhs or "");
	if lhs == rhs then
		return 0;
	end
	return lhs < rhs and -1 or 1;
end

FindValueInTableIf = FindValueInTableIf or function(tbl, predicate)
	for _, value in pairs(tbl) do
		if predicate(value) then
			return value;
		end
	end
end

---------------------------------------------------------------------------
-- пулы фреймов для колонок и заголовков
---------------------------------------------------------------------------
if not CreateFramePoolCollection then
	local FramePoolMixin = {};

	function FramePoolMixin:Acquire()
		local frame = tremove(self.free);
		if not frame then
			frame = CreateFrame(self.frameType, nil, self.parent, self.template);
			frame.framePool = self;
		end
		self.active[frame] = true;
		return frame, true;
	end

	function FramePoolMixin:Release(frame)
		if not self.active[frame] then
			return false;
		end
		self.active[frame] = nil;
		frame:Hide();
		frame:ClearAllPoints();
		tinsert(self.free, frame);
		return true;
	end

	function FramePoolMixin:ReleaseAll()
		for frame in pairs(self.active) do
			self:Release(frame);
		end
	end

	function FramePoolMixin:EnumerateActive()
		return pairs(self.active);
	end

	local FramePoolCollectionMixin = {};

	function FramePoolCollectionMixin:GetOrCreatePool(frameType, parent, template)
		local key = (frameType or "Frame") .. "|" .. tostring(parent) .. "|" .. tostring(template);
		local pool = self.pools[key];
		if not pool then
			pool = CreateFromMixins(FramePoolMixin);
			pool.frameType = frameType or "Frame";
			pool.parent = parent;
			pool.template = template;
			pool.free = {};
			pool.active = {};
			self.pools[key] = pool;
		end
		return pool;
	end

	function FramePoolCollectionMixin:ReleaseAll()
		for _, pool in pairs(self.pools) do
			pool:ReleaseAll();
		end
	end

	function FramePoolCollectionMixin:EnumerateActive()
		local frames = {};
		for _, pool in pairs(self.pools) do
			for frame in pairs(pool.active) do
				tinsert(frames, frame);
			end
		end
		local index = 0;
		return function()
			index = index + 1;
			return frames[index];
		end
	end

	function CreateFramePoolCollection()
		local collection = CreateFromMixins(FramePoolCollectionMixin);
		collection.pools = {};
		return collection;
	end
end
