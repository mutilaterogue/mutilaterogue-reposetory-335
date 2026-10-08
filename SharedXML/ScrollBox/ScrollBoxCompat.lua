-- ScrollBox (TWW) -> 3.3.5a: недостающие утилиты. Грузится первым в пакете.
-- Всё под guard'ами: если у тебя уже есть своя версия функции, она не перезаписывается.

---------------------------------------------------------------------------
-- MathUtil
---------------------------------------------------------------------------
MathUtil = MathUtil or {};
MathUtil.Epsilon = MathUtil.Epsilon or 0.000001;

Saturate = Saturate or function(value) return math.min(math.max(value, 0), 1); end
Clamp = Clamp or function(value, minValue, maxValue) return math.min(math.max(value, minValue), maxValue); end
Round = Round or function(value) return math.floor(value + 0.5); end
ApproximatelyEqual = ApproximatelyEqual or function(v1, v2, epsilon) return math.abs(v1 - v2) < (epsilon or MathUtil.Epsilon); end
WithinRange = WithinRange or function(value, minValue, maxValue) return value >= minValue and value <= maxValue; end
WithinRangeExclusive = WithinRangeExclusive or function(value, minValue, maxValue) return value > minValue and value < maxValue; end
NegateIf = NegateIf or function(value, condition) return condition and -value or value; end

PercentageBetween = PercentageBetween or function(value, startValue, endValue)
	if startValue == endValue then
		return 0;
	end
	return (value - startValue) / (endValue - startValue);
end

ClampedPercentageBetween = ClampedPercentageBetween or function(value, startValue, endValue)
	return Saturate(PercentageBetween(value, startValue, endValue));
end

---------------------------------------------------------------------------
-- TableUtil / FunctionUtil
---------------------------------------------------------------------------
CreateAndInitFromMixin = CreateAndInitFromMixin or function(mixin, ...)
	local object = CreateFromMixins(mixin);
	object:Init(...);
	return object;
end

tIndexOf = tIndexOf or function(tbl, item)
	for index, value in ipairs(tbl) do
		if value == item then
			return index;
		end
	end
end

CopyTable = CopyTable or function(settings, shallow)
	local copy = {};
	for k, v in pairs(settings) do
		if type(v) == "table" and not shallow then
			copy[k] = CopyTable(v);
		else
			copy[k] = v;
		end
	end
	return copy;
end

CopyValuesAsKeys = CopyValuesAsKeys or function(tbl)
	local result = {};
	for _, value in ipairs(tbl) do
		result[value] = value;
	end
	return result;
end

MergeTable = MergeTable or function(destination, source)
	for k, v in pairs(source) do
		destination[k] = v;
	end
end

ipairs_reverse = ipairs_reverse or function(tbl)
	local index = #tbl + 1;
	return function()
		index = index - 1;
		if index > 0 then
			return index, tbl[index];
		end
	end
end

EnumerateRange = EnumerateRange or function(indexBegin, indexEnd)
	local index = indexBegin - 1;
	return function()
		index = index + 1;
		if index <= indexEnd then
			return index, index;
		end
	end
end

CreateTableEnumerator = CreateTableEnumerator or function(tbl, indexBegin, indexEnd)
	indexBegin = indexBegin and (indexBegin - 1) or 0;
	indexEnd = indexEnd or math.huge;
	return function(_, index)
		index = index + 1;
		if index <= indexEnd then
			local value = tbl[index];
			if value ~= nil then
				return index, value;
			end
		end
	end, tbl, indexBegin;
end

CreateTableReverseEnumerator = CreateTableReverseEnumerator or function(tbl, indexBegin, indexEnd)
	indexBegin = (indexBegin or #tbl) + 1;
	indexEnd = indexEnd or 1;
	return function(_, index)
		index = index - 1;
		if index >= indexEnd then
			local value = tbl[index];
			if value ~= nil then
				return index, value;
			end
		end
	end, tbl, indexBegin;
end

FlagsUtil = FlagsUtil or {};
FlagsUtil.MakeFlags = FlagsUtil.MakeFlags or function(...)
	local flags = {};
	for index = 1, select("#", ...) do
		flags[select(index, ...)] = bit.lshift(1, index - 1);
	end
	return flags;
end

CreateVector2D = CreateVector2D or function(x, y)
	return { x = x or 0, y = y or 0, GetXY = function(self) return self.x, self.y; end };
end

NarrationUtil = NarrationUtil or { MakeIndexInfo = function() end };

---------------------------------------------------------------------------
-- время кадра (Interpolator) и курсор
---------------------------------------------------------------------------
if not GetTickTime then
	local tickTime = 0;
	local tickFrame = CreateFrame("Frame");
	tickFrame:SetScript("OnUpdate", function(self, elapsed)
		tickTime = elapsed;
	end);
	function GetTickTime()
		return tickTime;
	end
end

if not GetCursorDelta then
	local lastX, lastY;
	function GetCursorDelta()
		local x, y = GetCursorPosition();
		local dx, dy = 0, 0;
		if lastX then
			dx, dy = x - lastX, y - lastY;
		end
		lastX, lastY = x, y;
		return dx, dy;
	end
end

GetAppropriateTopLevelParent = GetAppropriateTopLevelParent or function() return UIParent; end

FrameUtil = FrameUtil or {};
FrameUtil.GetRootParent = FrameUtil.GetRootParent or function(frame)
	local parent = frame;
	while parent:GetParent() and parent:GetParent() ~= UIParent do
		parent = parent:GetParent();
	end
	return parent;
end

-- точка привязки по имени (вместо ретейлового region:GetPointByName)
function GetPointByNameSafe(region, name)
	for i = 1, region:GetNumPoints() do
		local point, relativeTo, relativePoint, x, y = region:GetPoint(i);
		if point == name then
			return point, relativeTo, relativePoint, x, y;
		end
	end
end

---------------------------------------------------------------------------
-- DesaturateHierarchy: ретейловый метод фреймов, его зовёт ButtonStateBehavior
---------------------------------------------------------------------------
if ButtonStateBehaviorMixin and not ButtonStateBehaviorMixin.DesaturateHierarchy then
	local function DesaturateRegions(frame, desaturate)
		for _, region in ipairs({ frame:GetRegions() }) do
			if region.SetDesaturated then
				region:SetDesaturated(desaturate);
			end
		end
		for _, child in ipairs({ frame:GetChildren() }) do
			DesaturateRegions(child, desaturate);
		end
	end

	function ButtonStateBehaviorMixin:DesaturateHierarchy(desaturate)
		DesaturateRegions(self, desaturate);
	end
end

---------------------------------------------------------------------------
-- AdjustPointsOffset / ClearPointsOffset: в 3.3.5 их нет, а ButtonStateBehavior
-- сдвигает ими текстуры при нажатии. Переопределяем сам миксин, метатаблицы не трогаем.
---------------------------------------------------------------------------
if ButtonStateBehaviorMixin then
	local function ShiftRegions(regions, x, y)
		for _, region in ipairs(regions or {}) do
			if region.AdjustPointsOffset then
				region:AdjustPointsOffset(x, y);
			else
				-- запоминаем исходные точки и двигаем их сами
				if not region.basePoints then
					region.basePoints = {};
					for i = 1, region:GetNumPoints() do
						local point, relativeTo, relativePoint, px, py = region:GetPoint(i);
						table.insert(region.basePoints, { point, relativeTo, relativePoint, px or 0, py or 0 });
					end
				end

				region:ClearAllPoints();
				for _, base in ipairs(region.basePoints) do
					region:SetPoint(base[1], base[2], base[3], base[4] + x, base[5] + y);
				end
			end
		end
	end

	local function ResetRegions(regions)
		for _, region in ipairs(regions or {}) do
			if region.ClearPointsOffset then
				region:ClearPointsOffset();
			elseif region.basePoints then
				region:ClearAllPoints();
				for _, base in ipairs(region.basePoints) do
					region:SetPoint(base[1], base[2], base[3], base[4], base[5]);
				end
			end
		end
	end

	function ButtonStateBehaviorMixin:OnMouseDown()
		if not self:IsEnabled() then
			return false;
		end
		self.down = true;
		ShiftRegions(self.displacedRegions, self.displaceX or 0, self.displaceY or 0);
		self:OnButtonStateChanged();
		return true;
	end

	function ButtonStateBehaviorMixin:OnMouseUp()
		if not self:IsEnabled() then
			return false;
		end
		self.down = nil;
		ResetRegions(self.displacedRegions);
		self:OnButtonStateChanged();
		return true;
	end

	function ButtonStateBehaviorMixin:OnDisable()
		self.over = nil;
		self.down = nil;
		ResetRegions(self.displacedRegions);

		if self.desaturateIfDisabled then
			self:DesaturateHierarchy(1);
		end

		self:OnButtonStateChanged();
	end
end

---------------------------------------------------------------------------
-- C_XMLUtil.GetTemplateInfo: в 3.3.5 нет — размер шаблона узнаём, создав пробный фрейм
---------------------------------------------------------------------------
C_XMLUtil = C_XMLUtil or {};

local templateTypes = {};		-- явная регистрация типа: C_XMLUtil.RegisterTemplateType("MyButtonTemplate", "Button")
local templateInfos = {};
local probeParent = CreateFrame("Frame");
probeParent:Hide();

local FRAME_TYPES = { Frame = true, Button = true, CheckButton = true, EditBox = true, ScrollFrame = true, StatusBar = true, Slider = true, Cooldown = true };

function C_XMLUtil.RegisterTemplateType(template, frameType)
	templateTypes[template] = frameType;
	templateInfos[template] = nil;
end

local function GuessTemplateType(template)
	if templateTypes[template] then
		return templateTypes[template];
	end
	if strfind(template, "CheckButton") then
		return "CheckButton";
	elseif strfind(template, "Button") then
		return "Button";
	elseif strfind(template, "EditBox") then
		return "EditBox";
	elseif strfind(template, "StatusBar") then
		return "StatusBar";
	end
	return "Frame";
end

if not C_XMLUtil.GetTemplateInfo then
	function C_XMLUtil.GetTemplateInfo(template)
		if not template or FRAME_TYPES[template] then
			return nil;
		end
		local info = templateInfos[template];
		if info == nil then
			local frameType = GuessTemplateType(template);
			local ok, probe = pcall(CreateFrame, frameType, nil, probeParent, template);
			if ok and probe then
				info = { type = frameType, width = probe:GetWidth(), height = probe:GetHeight(), keyValues = {}, inherits = "" };
				probe:Hide();
			else
				info = false;
			end
			templateInfos[template] = info;
		end
		return info or nil;
	end
end

---------------------------------------------------------------------------
-- FrameFactory + TemplateInfoCache (ScrollBoxListView)
---------------------------------------------------------------------------
if not CreateFrameFactory then
	local TemplateInfoCacheMixin = {};

	function TemplateInfoCacheMixin:GetTemplateInfo(template)
		local info = self.infos[template];
		if not info then
			info = C_XMLUtil.GetTemplateInfo(template);
			if not info and FRAME_TYPES[template] then
				info = { type = template, width = 0, height = 0, keyValues = {}, inherits = "" };
			end
			self.infos[template] = info;
		end
		return info;
	end

	function TemplateInfoCacheMixin:GetTemplateInfos()
		return self.infos;
	end

	function TemplateInfoCacheMixin:FlushTemplateInfos()
		wipe(self.infos);
	end

	local FrameFactoryMixin = {};

	local function DefaultResetter(pool, frame)
		frame:Hide();
		frame:ClearAllPoints();
	end

	function FrameFactoryMixin:Create(parent, templateOrType, resetter)
		local key = templateOrType;
		local pool = self.pools[key];
		if not pool then
			pool = { free = {} };
			self.pools[key] = pool;
		end

		local frame = tremove(pool.free);
		local isNew = false;
		if frame then
			frame:SetParent(parent);
		else
			local frameType, template = templateOrType, nil;
			if not FRAME_TYPES[templateOrType] then
				local info = self.templateInfoCache:GetTemplateInfo(templateOrType);
				frameType = info and info.type or "Frame";
				template = templateOrType;
			end
			frame = CreateFrame(frameType, nil, parent, template);
			frame.frameFactoryKey = key;
			isNew = true;
		end
		frame.frameFactoryResetter = resetter;
		self.active[frame] = true;
		return frame, isNew;
	end

	function FrameFactoryMixin:Release(frame)
		if not self.active[frame] then
			return false;
		end
		self.active[frame] = nil;
		(frame.frameFactoryResetter or DefaultResetter)(self, frame);
		tinsert(self.pools[frame.frameFactoryKey].free, frame);
		return true;
	end

	function FrameFactoryMixin:ReleaseAll()
		for frame in pairs(self.active) do
			self:Release(frame);
		end
	end

	function FrameFactoryMixin:GetTemplateInfoCache()
		return self.templateInfoCache;
	end

	function CreateFrameFactory()
		local cache = CreateFromMixins(TemplateInfoCacheMixin);
		cache.infos = {};
		local factory = CreateFromMixins(FrameFactoryMixin);
		factory.pools = {};
		factory.active = {};
		factory.templateInfoCache = cache;
		return factory;
	end
end

---------------------------------------------------------------------------
-- IndexRangeDataProvider (виртуальный список 1..N, им пользуется список лотов аукциона)
---------------------------------------------------------------------------
if not CreateIndexRangeDataProvider then
	IndexRangeDataProviderMixin = CreateFromMixins(CallbackRegistryMixin);
	IndexRangeDataProviderMixin:GenerateCallbackEvents({ "OnSizeChanged", "OnInsert", "OnRemove", "OnSort", "OnMove" });

	function IndexRangeDataProviderMixin:Init(size)
		CallbackRegistryMixin.OnLoad(self);
		self.size = size or 0;
	end

	function IndexRangeDataProviderMixin:IsVirtual() return true; end
	function IndexRangeDataProviderMixin:GetSize() return self.size; end
	function IndexRangeDataProviderMixin:IsEmpty() return self.size == 0; end

	function IndexRangeDataProviderMixin:SetSize(size)
		if self.size ~= size then
			self.size = size;
			self:TriggerEvent("OnSizeChanged", false);
		end
	end

	function IndexRangeDataProviderMixin:Flush()
		self:SetSize(0);
	end

	function IndexRangeDataProviderMixin:Enumerate(indexBegin, indexEnd)
		return EnumerateRange(indexBegin or 1, math.min(indexEnd or self.size, self.size));
	end
	IndexRangeDataProviderMixin.EnumerateEntireRange = IndexRangeDataProviderMixin.Enumerate;

	function IndexRangeDataProviderMixin:ReverseEnumerate(indexBegin, indexEnd)
		local index = math.min(indexBegin or self.size, self.size) + 1;
		local last = indexEnd or 1;
		return function()
			index = index - 1;
			if index >= last then
				return index, index;
			end
		end
	end
	IndexRangeDataProviderMixin.ReverseEnumerateEntireRange = IndexRangeDataProviderMixin.ReverseEnumerate;

	function IndexRangeDataProviderMixin:Find(index)
		return (index >= 1 and index <= self.size) and index or nil;
	end

	function IndexRangeDataProviderMixin:FindIndex(elementData)
		return self:Find(elementData), elementData;
	end

	function IndexRangeDataProviderMixin:FindByPredicate(predicate)
		for index = 1, self.size do
			if predicate(index) then
				return index, index;
			end
		end
	end

	function IndexRangeDataProviderMixin:FindElementDataByPredicate(predicate)
		return (select(2, self:FindByPredicate(predicate)));
	end

	function IndexRangeDataProviderMixin:FindIndexByPredicate(predicate)
		return (self:FindByPredicate(predicate));
	end

	function IndexRangeDataProviderMixin:ContainsByPredicate(predicate)
		return self:FindByPredicate(predicate) ~= nil;
	end

	function IndexRangeDataProviderMixin:ForEach(func)
		for index = 1, self.size do
			func(index);
		end
	end

	function CreateIndexRangeDataProvider(size)
		return CreateAndInitFromMixin(IndexRangeDataProviderMixin, size);
	end
end
