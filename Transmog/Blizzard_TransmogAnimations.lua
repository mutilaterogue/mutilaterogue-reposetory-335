-- Анимации окна трансмогрификации (ретейл: <Animations> в Blizzard_TransmogTemplates.xml / Blizzard_Transmog.xml).
-- В 3.3.5 нет FlipBook, fromAlpha/toAlpha, childKey и setToFinalAlpha, поэтому группы анимаций
-- проигрываются здесь, в Lua; значения (длительности, задержки, раскадровки) - те же, что в ретейле.
--
-- Дорожка: { ключ текстуры, тип, startDelay, duration, ... }
--   "alpha" : fromAlpha, toAlpha[, endDelay]
--   "flip"  : rows, columns, frames, атлас (кадры режутся по координатам атласа)
--   "move"  : offsetX, offsetY (Translation)
-- Как в ретейле с setToFinalAlpha: у текстуры действует последняя начавшаяся дорожка,
-- а до начала первой - её fromAlpha.

TransmogAnim = {};

local active = {};
local driver = CreateFrame("Frame");
driver:Hide();
driver:SetScript("OnUpdate", function(self, elapsed)
	-- копия списка: OnFinished может запускать/останавливать другие анимации (pairs по изменяемой таблице ломается)
	local list = {};
	for anim in pairs(active) do
		list[#list + 1] = anim;
	end
	for _, anim in ipairs(list) do
		if active[anim] then
			anim:Tick(elapsed);
		end
	end
	if not next(active) then
		self:Hide();
	end
end);

local function Clamp01(value)
	if value < 0 then
		return 0;
	elseif value > 1 then
		return 1;
	end
	return value;
end

local function Progress(track, t)
	if track[4] <= 0 then
		return 1;
	end
	return Clamp01((t - track[3]) / track[4]);
end

local AnimMixin = {};

function AnimMixin:Apply(t)
	-- альфа: по текстуре, дорожки отсортированы по задержке
	for texture, tracks in pairs(self.alpha) do
		local value = tracks[1][5];
		for _, track in ipairs(tracks) do
			if t >= track[3] then
				local p = Progress(track, t);
				value = track[5] + (track[6] - track[5]) * p;
			end
		end
		texture:SetAlpha(value);
	end

	for _, track in ipairs(self.flips) do
		local texture, info = track.texture, track.info;
		local frames = track[7];
		local frame = 1;
		if t >= track[3] then
			frame = math.min(frames, math.floor(Progress(track, t) * frames) + 1);
		end
		if info then
			local columns = track[6];
			local col = (frame - 1) % columns;
			local row = math.floor((frame - 1) / columns);
			local w = (info.right - info.left) / columns;
			local h = (info.bottom - info.top) / track[5];
			local l, top = info.left + col * w, info.top + row * h;
			texture:SetTexCoord(l, l + w, top, top + h);
		end
	end

	for _, track in ipairs(self.moves) do
		local p = t >= track[3] and Progress(track, t) or 0;
		local base = track.base;
		track.texture:SetPoint(base[1], base[2], base[3], base[4] + track[5] * p, base[5] + track[6] * p);
	end
end

function AnimMixin:Tick(elapsed)
	local t = self.time + elapsed;
	if t >= self.duration then
		if self.looping then
			t = t % self.duration;
		else
			self.time = self.duration;
			self:Apply(self.duration);
			active[self] = nil;
			if self.onFinished then
				self.onFinished(self);
			end
			return;
		end
	end
	self.time = t;
	self:Apply(t);
end

function AnimMixin:Restart()
	self.time = 0;
	self:Apply(0);
	active[self] = true;
	driver:Show();
end
AnimMixin.Play = AnimMixin.Restart;

function AnimMixin:Stop()
	active[self] = nil;
end

-- без проигрыша - сразу конечное состояние (setToFinalAlpha)
function AnimMixin:Finish()
	active[self] = nil;
	self.time = self.duration;
	self:Apply(self.duration);
end

function AnimMixin:IsPlaying()
	return active[self] ~= nil;
end

function AnimMixin:SetScript(script, func)
	if script == "OnFinished" then
		self.onFinished = func;
	end
end

local function GetAtlasCoords(atlas)
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas);
	if not info then
		return nil;
	end
	local left = info.leftTexCoord or info.left;
	local right = info.rightTexCoord or info.right;
	local top = info.topTexCoord or info.top;
	local bottom = info.bottomTexCoord or info.bottom;
	if left and right and top and bottom then
		return { left = left, right = right, top = top, bottom = bottom };
	end
end

-- frame[key] - текстуры, def - список дорожек
function TransmogAnim.Create(frame, def, looping)
	local anim = { alpha = {}, flips = {}, moves = {}, time = 0, duration = 0, looping = looping };
	for name, func in pairs(AnimMixin) do
		anim[name] = func;
	end

	for index, track in ipairs(def) do
		local texture = frame[track[1]];
		if texture then
			local kind = track[2];
			local copy = { unpack(track) };
			copy.texture, copy.index = texture, index;
			local finish = track[3] + track[4];
			if kind == "alpha" then
				finish = finish + (track[7] or 0);
				anim.alpha[texture] = anim.alpha[texture] or {};
				table.insert(anim.alpha[texture], copy);
			elseif kind == "flip" then
				copy.info = GetAtlasCoords(track[8]);
				table.insert(anim.flips, copy);
			elseif kind == "move" then
				local point, relativeTo, relativePoint, x, y = texture:GetPoint(1);
				copy.base = { point, relativeTo, relativePoint, x or 0, y or 0 };
				table.insert(anim.moves, copy);
			end
			anim.duration = math.max(anim.duration, finish);
		end
	end

	for _, tracks in pairs(anim.alpha) do
		table.sort(tracks, function(a, b)
			if a[3] ~= b[3] then
				return a[3] < b[3];
			end
			return a.index < b.index;
		end);
	end

	if anim.duration <= 0 then
		anim.duration = 0.01;
	end
	if not looping then
		anim:Finish();
	end
	return anim;
end

---------------------------------------------------------------------------
-- группы ретейла
---------------------------------------------------------------------------
local START = "transmog-gearSlot-flipbook-start";

-- TransmogAppearanceSlotTemplate.PendingFrame.AnimStart
TransmogAnim.SLOT_PENDING_START = {
	{ "FlipbookStart", "flip", 0, 0.8, 4, 6, 24, START },
	{ "FlipbookStart", "alpha", 0, 1, 1, 1, 0.8 },
	{ "FlipbookStart", "alpha", 0.8, 1, 0, 0, 0.81 },
	{ "Highlight", "alpha", 0, 0.47, 1, 1 },
	{ "Highlight", "alpha", 0.47, 0.5, 1, 0 },
	{ "Glow", "alpha", 0, 0.33, 1, 1 },
	{ "Glow", "alpha", 0.33, 0.33, 1, 0 },
};

-- TransmogAppearanceSlotTemplate.PendingFrame.AnimLoop (looping="REPEAT")
TransmogAnim.SLOT_PENDING_LOOP = {
	{ "FlipbookLeft", "flip", 0, 2.3, 2, 55, 70, "transmog-gearSlot-flipbook-loop-Left" },
	{ "FlipbookRight", "flip", 0, 2.3, 2, 55, 70, "transmog-gearSlot-flipbook-loop-Right" },
	{ "FlipbookTop", "flip", 0, 2.3, 7, 10, 70, "transmog-gearSlot-flipbook-loop-Top" },
	{ "FlipbookBottom", "flip", 0, 2.3, 7, 10, 70, "transmog-gearSlot-flipbook-loop-Bottom" },
};

-- TransmogAppearanceSlotTemplate.SavedFrame.Anim
TransmogAnim.SLOT_SAVED = {
	{ "FlipbookSparks", "flip", 0.33, 0.8, 4, 6, 24, "transmog-gearSlot-flipbook-sparks" },
	{ "FlipbookSparks", "alpha", 0, 0.33, 0, 0 },
	{ "FlipbookSparks", "alpha", 0.33, 0.8, 1, 1 },
	{ "BackgroundFX", "alpha", 0, 0.33, 1, 1 },
	{ "BackgroundFX", "alpha", 0.33, 0.23, 1, 0 },
	{ "FrameGlow", "alpha", 0, 0.17, 1, 1 },
	{ "FrameGlow", "alpha", 0.17, 0.17, 1, 0 },
	{ "FlipbookStart", "flip", 0.5, 0.8, 4, 6, 24, START },
	{ "FlipbookStart", "alpha", 0, 0.5, 0, 0 },
	{ "FlipbookStart", "alpha", 0.5, 0.8, 1, 1 },
	{ "FlipbookStart", "alpha", 1.3, 0.1, 1, 0 },
	{ "LineSquare", "alpha", 0, 0.5, 1, 1 },
	{ "LineSquare", "alpha", 0.5, 0.17, 1, 0 },
	{ "Highlight", "alpha", 0, 0.73, 1, 1 },
	{ "Highlight", "alpha", 0.73, 0.3, 1, 0 },
	{ "Glow", "alpha", 0, 0.5, 1, 1 },
	{ "Glow", "alpha", 0.5, 0.23, 1, 0 },
};

-- TransmogFrame.CharacterPreview.SavedFrame.Anim - вспышка на полу под моделью (Glow -> SavedGlow)
TransmogAnim.PREVIEW_SAVED = {
	{ "LinesFade1FX", "alpha", 0, 0.4, 0, 0 },
	{ "LinesFade1FX", "alpha", 0.4, 0.13, 0, 0.17 },
	{ "LinesFade1FX", "alpha", 0.53, 0.4, 0.17, 0 },
	{ "LinesFade2FX", "alpha", 0, 0.4, 0, 0 },
	{ "LinesFade2FX", "alpha", 0.4, 0.13, 0, 0.17 },
	{ "LinesFade2FX", "alpha", 0.53, 0.4, 0.17, 0 },
	{ "LinesFade3FX", "alpha", 0, 0.27, 0, 0 },
	{ "LinesFade3FX", "alpha", 0.27, 0.27, 0, 0.17 },
	{ "LinesFade3FX", "alpha", 0.54, 0.57, 0.17, 0 },
	{ "LinesFade4FX", "alpha", 0, 0.27, 0, 0 },
	{ "LinesFade4FX", "alpha", 0.27, 0.27, 0, 0.17 },
	{ "LinesFade4FX", "alpha", 0.54, 0.57, 0.17, 0 },
	{ "LinesFade5FX", "alpha", 0, 0.27, 0, 0 },
	{ "LinesFade5FX", "alpha", 0.27, 0.13, 0, 0.4 },
	{ "LinesFade5FX", "alpha", 0.4, 0.53, 0.4, 0 },
	{ "Rays1FX", "alpha", 0, 0.33, 0, 0.35 },
	{ "Rays1FX", "alpha", 0.33, 1, 0.35, 0 },
	{ "Rays1FX", "move", 0.33, 1, 0, 20 },
	{ "Rays2FX", "alpha", 0, 0.33, 0, 0.35 },
	{ "Rays2FX", "alpha", 0.33, 1, 0.35, 0 },
	{ "Rays2FX", "move", 0.33, 1, 0, 20 },
	{ "LinesGlowFX", "alpha", 0, 0.17, 0, 0.2 },
	{ "LinesGlowFX", "alpha", 0.17, 0.67, 0.2, 0 },
	{ "SavedGlow", "alpha", 0, 0.33, 0, 1 },
	{ "SavedGlow", "alpha", 0.33, 0.2, 1, 1 },
	{ "SavedGlow", "alpha", 0.53, 0.47, 1, 0 },
};

-- TransmogItemModelTemplate / TransmogSetBaseModelTemplate .PendingFrame.Anim (looping="REPEAT")
TransmogAnim.CARD_PENDING = {
	{ "PendingFX", "alpha", 0, 1, 0, 1 },
	{ "PendingFX", "alpha", 1, 1.33, 1, 0 },
	{ "FlipbookTop", "flip", 0, 2.33, 7, 10, 70, "transmog-itemSlot-flipbook-loop-Top" },
	{ "FlipbookBottom", "flip", 0, 2.33, 7, 10, 70, "transmog-itemSlot-flipbook-loop-Bottom" },
	{ "FlipbookRight", "flip", 0, 2.33, 3, 30, 70, "transmog-itemSlot-flipbook-loop-Right" },
	{ "FlipbookLeft", "flip", 0, 2.33, 3, 30, 70, "transmog-itemSlot-flipbook-loop-Left" },
	{ "SmokeFXLeft", "move", 0, 2.33, 0, 30 },
	{ "SmokeFXLeft", "alpha", 0, 1, 0, 1 },
	{ "SmokeFXLeft", "alpha", 1, 1.33, 1, 0 },
	{ "SmokeFXRight", "move", 0, 2.33, 0, -20 },
	{ "SmokeFXRight", "alpha", 0, 0.5, 0, 1 },
	{ "SmokeFXRight", "alpha", 0.5, 1.83, 1, 0 },
	{ "SmokeFXTop", "move", 0, 2.33, 20, 0 },
	{ "SmokeFXTop", "alpha", 0, 1, 0, 1 },
	{ "SmokeFXTop", "alpha", 1, 1.33, 1, 0 },
	{ "SmokeFXBottom", "move", 0, 2.33, -20, 0 },
	{ "SmokeFXBottom", "alpha", 0, 0.83, 0, 0.6 },
	{ "SmokeFXBottom", "alpha", 0.83, 1.5, 0.6, 0 },
};

local function CardSaved(sideDuration, sparksTo)
	return {
		{ "FlipbookSparks", "alpha", 0, 0, 0, 0 },
		{ "FlipbookSparks", "alpha", 0.33, 0.6, 1, sparksTo },
		{ "FlipbookSparks", "flip", 0.33, 0.6, 3, 6, 18, "transmog-itemSlot-flipbook-sparks" },
		{ "FlipbookLeft", "flip", 0, 0.4, 1, 14, 14, "transmog-itemSlot-flipbook-startLeft" },
		{ "FlipbookRight", "flip", 0, 0.4, 1, 14, 14, "transmog-itemSlot-flipbook-startRight" },
		{ "FlipbookTop", "flip", 0, sideDuration, 3, 4, 12, "transmog-itemSlot-flipbook-startTop" },
		{ "FlipbookBottom", "flip", 0, sideDuration, 3, 4, 12, "transmog-itemSlot-flipbook-startBottom" },
		{ "Electrified1", "alpha", 0, 0.2, 0, 1 },
		{ "Electrified1", "alpha", 0.2, 0.63, 1, 1 },
		{ "Electrified1", "alpha", 0.83, 0.23, 1, 0 },
		{ "Electrified2", "alpha", 0, 0.33, 0, 0 },
		{ "Electrified2", "alpha", 0.33, 0.2, 1, 0 },
	};
end
-- .SavedFrame.Anim: карточка предмета / карточка комплекта
TransmogAnim.ITEMCARD_SAVED = CardSaved(0.4, 1);
TransmogAnim.SETCARD_SAVED = CardSaved(0.43, 0.7);

-- TransmogOutfitEntryTemplate.OutfitButton.AnimSaved / AnimNew
TransmogAnim.OUTFIT_SAVED = {
	{ "GlowPurple", "alpha", 0, 1.2, 1, 1 },
	{ "GlowPurple", "alpha", 1.2, 0.3, 1, 0 },
	{ "SelectedPurple", "alpha", 0, 1.2, 1, 1 },
	{ "SelectedPurple", "alpha", 1.2, 0.3, 1, 0 },
	{ "Selected", "alpha", 0, 1.2, 0, 0 },
	{ "Selected", "alpha", 1.2, 0.3, 0, 1 },
};
TransmogAnim.OUTFIT_NEW = {
	{ "Glow", "alpha", 0, 0.24, 1, 1 },
	{ "Glow", "alpha", 0.24, 0.3, 1, 0 },
};

---------------------------------------------------------------------------
-- эффекты карточек (ретейл: PendingFrame/SavedFrame в TransmogItemModelTemplate и TransmogSetBaseModelTemplate).
-- Карточки - DressUpModel, области модели рисуются под ней, поэтому эффекты - в отдельных кадрах над карточкой.
-- Текстура: { ключ, атлас, ширина или nil (размер атласа), высота, x, y }
---------------------------------------------------------------------------
TransmogAnim.ITEMCARD_FX = {
	pending = {
		{ "SmokeFXRight", "transmog-itemCard-transmogrified-pending-FX3", nil, nil, 44, 1 },
		{ "SmokeFXLeft", "transmog-itemCard-transmogrified-pending-FX3", nil, nil, -54, -10 },
		{ "SmokeFXTop", "transmog-itemCard-transmogrified-pending-FX2", nil, nil, -10, 65 },
		{ "SmokeFXBottom", "transmog-itemCard-transmogrified-pending-FX2", nil, nil, 10, -63 },
		{ "FlipbookRight", "transmog-itemSlot-flipbook-loop-Right", 17, 134, 52, 0 },
		{ "FlipbookLeft", "transmog-itemSlot-flipbook-loop-Left", 17, 134, -52, 0 },
		{ "FlipbookTop", "transmog-itemSlot-flipbook-loop-Top", 99, 17, 0, 67 },
		{ "FlipbookBottom", "transmog-itemSlot-flipbook-loop-Bottom", 99, 17, 0, -68 },
		{ "PendingFX", "transmog-itemCard-transmogrified-pending-FX1", nil, nil, 0, 0 },
	},
	saved = {
		{ "FlipbookRight", "transmog-itemSlot-flipbook-startRight", 35, 165, 53, 0 },
		{ "FlipbookLeft", "transmog-itemSlot-flipbook-startLeft", 35, 165, -53, 0 },
		{ "FlipbookTop", "transmog-itemSlot-flipbook-startTop", 112, 25, 0, 68 },
		{ "FlipbookBottom", "transmog-itemSlot-flipbook-startBottom", 112, 25, 0, -68 },
		{ "Electrified1", "transmog-itemCard-electrified", nil, nil, 0, 0 },
		{ "Electrified2", "transmog-itemCard-electrified", nil, nil, 0, 0 },
		{ "FlipbookSparks", "transmog-itemSlot-flipbook-sparks", 150, 208, 8, 0 },
	},
	savedAnim = TransmogAnim.ITEMCARD_SAVED,
};

TransmogAnim.SETCARD_FX = {
	pending = {
		{ "SmokeFXRight", "transmog-setCard-transmogrified-pending-FX3", nil, nil, 88, 1 },
		{ "SmokeFXLeft", "transmog-setCard-transmogrified-pending-FX3", nil, nil, -92, 0 },
		{ "SmokeFXTop", "transmog-setCard-transmogrified-pending-FX2", nil, nil, 0, 108 },
		{ "SmokeFXBottom", "transmog-setCard-transmogrified-pending-FX2", nil, nil, 0, -108 },
		{ "FlipbookRight", "transmog-itemSlot-flipbook-loop-Right", 20, 230, 92, 0 },
		{ "FlipbookLeft", "transmog-itemSlot-flipbook-loop-Left", 20, 226, -92, 0 },
		{ "FlipbookTop", "transmog-itemSlot-flipbook-loop-Top", 180, 20, 0, 111 },
		{ "FlipbookBottom", "transmog-itemSlot-flipbook-loop-Bottom", 180, 20, 0, -112 },
		{ "PendingFX", "transmog-setCard-transmogrified-pending-FX1", 194, 234, 0, 0 },
	},
	saved = {
		{ "FlipbookRight", "transmog-itemSlot-flipbook-startRight", 55, 260, 90, 0 },
		{ "FlipbookLeft", "transmog-itemSlot-flipbook-startLeft", 55, 260, -90, 0 },
		{ "FlipbookTop", "transmog-itemSlot-flipbook-startTop", 225, 51, 0, 110 },
		{ "FlipbookBottom", "transmog-itemSlot-flipbook-startBottom", 225, 51, 0, -110 },
		{ "Electrified1", "transmog-itemCard-electrified", 215, 260, 0, 0 },
		{ "Electrified2", "transmog-itemCard-electrified", 215, 260, 0, 0 },
		{ "FlipbookSparks", "transmog-itemSlot-flipbook-sparks", 260, 290, 12, 0 },
	},
	savedAnim = TransmogAnim.SETCARD_SAVED,
};

local function CreateFXFrame(card, level, textures)
	local frame = CreateFrame("Frame", nil, card:GetParent());
	frame:SetAllPoints(card);
	frame:SetFrameLevel(level);
	frame:Hide();
	for _, info in ipairs(textures) do
		local texture = frame:CreateTexture(nil, "OVERLAY");
		texture:SetAtlas(info[2], not info[3]);
		if info[3] then
			texture:SetWidth(info[3]);
			texture:SetHeight(info[4]);
		end
		texture:SetPoint("CENTER", info[5], info[6]);
		frame[info[1]] = texture;
	end
	return frame;
end

-- card.PendingFrame (.Anim - цикл) и card.SavedFrame (.Anim - один раз); спрятать карточку - TransmogAnim.SetCardState(card)
function TransmogAnim.SetupCard(card, spec, level)
	local pending = CreateFXFrame(card, level, spec.pending);
	pending.Anim = TransmogAnim.Create(pending, TransmogAnim.CARD_PENDING, true);
	local saved = CreateFXFrame(card, level + 1, spec.saved);
	saved.Anim = TransmogAnim.Create(saved, spec.savedAnim);
	saved.Anim:SetScript("OnFinished", function()
		saved:Hide();
	end);
	card.PendingFrame, card.SavedFrame = pending, saved;
	-- эффекты лежат не на самой карточке - прятать вместе с ней
	card:HookScript("OnHide", function()
		pending.Anim:Stop();
		pending:Hide();
		saved.Anim:Stop();
		saved:Hide();
	end);
end

-- ретейл: TransmogItemModelMixin:UpdateState - цикл ожидания; playSaved - вспышка после применения
function TransmogAnim.SetCardState(card, hasPending, playSaved)
	local pending = card.PendingFrame;
	if hasPending and card:IsShown() then
		if not pending:IsShown() then
			pending:Show();
			pending.Anim:Restart();
		end
	else
		pending.Anim:Stop();
		pending:Hide();
	end
	if playSaved and card:IsShown() then
		card.SavedFrame:Show();
		card.SavedFrame.Anim:Restart();
	elseif not card:IsShown() then
		card.SavedFrame.Anim:Stop();
		card.SavedFrame:Hide();
	end
end
