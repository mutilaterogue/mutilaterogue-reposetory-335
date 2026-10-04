-- Pools.lua (Legion 7.3.5), адаптация под 3.3.5a
-- Правки: убран SecureCapsule-блок, добавлены nop/IsActive/Dump,
-- защищён Release от двойного вызова, исправлен PoolCollection:Acquire.

nop = nop or function() end

---------------------------------------------------------------------------
-- ObjectPool
---------------------------------------------------------------------------
ObjectPoolMixin = {};

function ObjectPoolMixin:OnLoad(creationFunc, resetterFunc)
	self.creationFunc = creationFunc;
	self.resetterFunc = resetterFunc;

	self.activeObjects = {};
	self.inactiveObjects = {};

	self.numActiveObjects = 0;
end

function ObjectPoolMixin:Acquire()
	local numInactiveObjects = #self.inactiveObjects;
	if numInactiveObjects > 0 then
		local obj = self.inactiveObjects[numInactiveObjects];
		self.inactiveObjects[numInactiveObjects] = nil;
		self.activeObjects[obj] = true;
		self.numActiveObjects = self.numActiveObjects + 1;
		return obj, false;
	end

	local newObj = self.creationFunc(self);
	if self.resetterFunc then
		self.resetterFunc(self, newObj);
	end
	self.activeObjects[newObj] = true;
	self.numActiveObjects = self.numActiveObjects + 1;
	return newObj, true;
end

-- возвращает true, если объект был активен и вернулся в пул
function ObjectPoolMixin:Release(obj)
	if obj == nil or not self.activeObjects[obj] then
		return false;
	end

	self.activeObjects[obj] = nil;
	self.numActiveObjects = self.numActiveObjects - 1;
	self.inactiveObjects[#self.inactiveObjects + 1] = obj;

	if self.resetterFunc then
		self.resetterFunc(self, obj);
	end

	return true;
end

function ObjectPoolMixin:ReleaseAll()
	-- копия ключей: безопасно, даже если resetter что-то меняет в таблице
	local list = {};
	for obj in pairs(self.activeObjects) do
		list[#list + 1] = obj;
	end
	for i = 1, #list do
		self:Release(list[i]);
	end
end

function ObjectPoolMixin:EnumerateActive()
	return pairs(self.activeObjects);
end

function ObjectPoolMixin:GetNextActive(current)
	return (next(self.activeObjects, current));
end

function ObjectPoolMixin:IsActive(obj)
	return self.activeObjects[obj] ~= nil;
end

function ObjectPoolMixin:GetNumActive()
	return self.numActiveObjects;
end

function ObjectPoolMixin:EnumerateInactive()
	return ipairs(self.inactiveObjects);
end

function ObjectPoolMixin:Dump()
	for obj in pairs(self.activeObjects) do
		print(tostring(obj));
	end
end

function CreateObjectPool(creationFunc, resetterFunc)
	local objectPool = CreateFromMixins(ObjectPoolMixin);
	objectPool:OnLoad(creationFunc, resetterFunc);
	return objectPool;
end

---------------------------------------------------------------------------
-- FramePool
---------------------------------------------------------------------------
FramePoolMixin = Mixin({}, ObjectPoolMixin);

local function FramePoolFactory(framePool)
	return CreateFrame(framePool.frameType, nil, framePool.parent, framePool.frameTemplate);
end

function FramePoolMixin:OnLoad(frameType, parent, frameTemplate, resetterFunc)
	ObjectPoolMixin.OnLoad(self, FramePoolFactory, resetterFunc);
	self.frameType = frameType;
	self.parent = parent;
	self.frameTemplate = frameTemplate;
end

function FramePoolMixin:GetTemplate()
	return self.frameTemplate;
end

function FramePool_Hide(framePool, frame)
	frame:Hide();
end

function FramePool_HideAndClearAnchors(framePool, frame)
	frame:Hide();
	frame:ClearAllPoints();
end

function CreateFramePool(frameType, parent, frameTemplate, resetterFunc)
	local framePool = CreateFromMixins(FramePoolMixin);
	framePool:OnLoad(frameType, parent, frameTemplate, resetterFunc or FramePool_HideAndClearAnchors);
	return framePool;
end

---------------------------------------------------------------------------
-- TexturePool (subLayer в 3.3.5 CreateTexture не поддерживается — игнорируется)
---------------------------------------------------------------------------
TexturePoolMixin = Mixin({}, ObjectPoolMixin);

local function TexturePoolFactory(texturePool)
	return texturePool.parent:CreateTexture(nil, texturePool.layer, texturePool.textureTemplate);
end

function TexturePoolMixin:OnLoad(parent, layer, subLayer, textureTemplate, resetterFunc)
	ObjectPoolMixin.OnLoad(self, TexturePoolFactory, resetterFunc);
	self.parent = parent;
	self.layer = layer;
	self.subLayer = subLayer;
	self.textureTemplate = textureTemplate;
end

function TexturePoolMixin:GetTemplate()
	return self.textureTemplate;
end

TexturePool_Hide = FramePool_Hide;
TexturePool_HideAndClearAnchors = FramePool_HideAndClearAnchors;

function CreateTexturePool(parent, layer, subLayer, textureTemplate, resetterFunc)
	local texturePool = CreateFromMixins(TexturePoolMixin);
	texturePool:OnLoad(parent, layer, subLayer, textureTemplate, resetterFunc or TexturePool_HideAndClearAnchors);
	return texturePool;
end

---------------------------------------------------------------------------
-- FontStringPool
---------------------------------------------------------------------------
FontStringPoolMixin = Mixin({}, ObjectPoolMixin);

local function FontStringPoolFactory(fontStringPool)
	return fontStringPool.parent:CreateFontString(nil, fontStringPool.layer, fontStringPool.fontStringTemplate);
end

function FontStringPoolMixin:OnLoad(parent, layer, subLayer, fontStringTemplate, resetterFunc)
	ObjectPoolMixin.OnLoad(self, FontStringPoolFactory, resetterFunc);
	self.parent = parent;
	self.layer = layer;
	self.subLayer = subLayer;
	self.fontStringTemplate = fontStringTemplate;
end

function FontStringPoolMixin:GetTemplate()
	return self.fontStringTemplate;
end

FontStringPool_Hide = FramePool_Hide;
FontStringPool_HideAndClearAnchors = FramePool_HideAndClearAnchors;

function CreateFontStringPool(parent, layer, subLayer, fontStringTemplate, resetterFunc)
	local fontStringPool = CreateFromMixins(FontStringPoolMixin);
	fontStringPool:OnLoad(parent, layer, subLayer, fontStringTemplate, resetterFunc or FontStringPool_HideAndClearAnchors);
	return fontStringPool;
end

---------------------------------------------------------------------------
-- ActorPool (в 3.3.5 нет ModelScene; пул создаётся, но Acquire упадёт без CreateActor)
---------------------------------------------------------------------------
ActorPoolMixin = Mixin({}, ObjectPoolMixin);

local function ActorPoolFactory(actorPool)
	assert(actorPool.parent.CreateActor, "CreateActor is not supported in 3.3.5");
	return actorPool.parent:CreateActor(nil, actorPool.actorTemplate);
end

function ActorPoolMixin:OnLoad(parent, actorTemplate, resetterFunc)
	ObjectPoolMixin.OnLoad(self, ActorPoolFactory, resetterFunc);
	self.parent = parent;
	self.actorTemplate = actorTemplate;
end

ActorPool_Hide = FramePool_Hide;
function ActorPool_HideAndClearModel(actorPool, actor)
	if actor.ClearModel then
		actor:ClearModel();
	end
	actor:Hide();
end

function CreateActorPool(parent, actorTemplate, resetterFunc)
	local actorPool = CreateFromMixins(ActorPoolMixin);
	actorPool:OnLoad(parent, actorTemplate, resetterFunc or ActorPool_HideAndClearModel);
	return actorPool;
end

---------------------------------------------------------------------------
-- PoolCollection
---------------------------------------------------------------------------
PoolCollection = {};

function CreatePoolCollection()
	local poolCollection = CreateFromMixins(PoolCollection);
	poolCollection:OnLoad();
	return poolCollection;
end

function PoolCollection:OnLoad()
	self.pools = {};
end

function PoolCollection:CreatePool(frameType, parent, template, resetterFunc)
	assert(template, "PoolCollection:CreatePool: template is required");
	assert(self:GetPool(template) == nil, "PoolCollection: pool already exists for " .. tostring(template));
	local pool = CreateFramePool(frameType, parent, template, resetterFunc);
	self.pools[template] = pool;
	return pool;
end

function PoolCollection:GetPool(template)
	return self.pools[template];
end

function PoolCollection:GetOrCreatePool(frameType, parent, template, resetterFunc)
	local pool = self:GetPool(template);
	if pool then
		return pool, false;
	end
	return self:CreatePool(frameType, parent, template, resetterFunc), true;
end

-- в оригинале тут вызывался CreatePool с неверными аргументами
function PoolCollection:Acquire(template)
	local pool = self:GetPool(template);
	assert(pool, "PoolCollection: no pool for template " .. tostring(template));
	return pool:Acquire();
end

-- поддерживаются обе формы: Release(template, obj) (7.3.5) и Release(obj) (8.x+)
function PoolCollection:Release(template, object)
	if object == nil then
		object = template;
		for _, pool in pairs(self.pools) do
			if pool:Release(object) then
				return true;
			end
		end
		geterrorhandler()("PoolCollection: object does not belong to any pool");
		return false;
	end

	local pool = self:GetPool(template);
	assert(pool, "PoolCollection: no pool for template " .. tostring(template));
	return pool:Release(object);
end

function PoolCollection:ReleaseAllByTemplate(template)
	local pool = self:GetPool(template);
	if pool then
		pool:ReleaseAll();
	end
end

function PoolCollection:ReleaseAll()
	for key, pool in pairs(self.pools) do
		pool:ReleaseAll();
	end
end

function PoolCollection:EnumerateActiveByTemplate(template)
	local pool = self:GetPool(template);
	if pool then
		return pool:EnumerateActive();
	end

	return nop;
end

function PoolCollection:GetNumActive()
	local total = 0;
	for _, pool in pairs(self.pools) do
		total = total + pool:GetNumActive();
	end
	return total;
end

function PoolCollection:IsActive(object)
	for _, pool in pairs(self.pools) do
		if pool:IsActive(object) then
			return true;
		end
	end
	return false;
end

-- возвращает только объект
function PoolCollection:EnumerateActive()
	local currentPoolKey, currentPool = next(self.pools, nil);
	local currentObject = nil;
	return function()
		if currentPool then
			currentObject = currentPool:GetNextActive(currentObject);
			while not currentObject do
				currentPoolKey, currentPool = next(self.pools, currentPoolKey);
				if currentPool then
					currentObject = currentPool:GetNextActive();
				else
					break;
				end
			end
		end

		return currentObject;
	end, nil;
end

-- алиас под имя из 8.x+
CreateFramePoolCollection = CreateFramePoolCollection or CreatePoolCollection;