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
