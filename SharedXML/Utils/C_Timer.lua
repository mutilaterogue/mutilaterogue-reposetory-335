-- C_Timer для 3.3.5a
-- В 7.3.5 C_Timer.After нативный, здесь он сделан через скрытый фрейм с OnUpdate.
-- NewTicker / NewTimer / Cancel взяты из C_TimerAugment.lua (7.3.5) без изменений логики.

C_Timer = C_Timer or {};

---------------------------------------------------------------------------
-- ядро: C_Timer.After
---------------------------------------------------------------------------
local waiting = {};   -- таймеры, добавленные в этом кадре (запустятся со следующего)
local active = {};    -- { at = time, fn = callback }
local tickTime = 0;

local driver = CreateFrame("Frame");
driver:Hide();

driver:SetScript("OnUpdate", function(self, elapsed)
	tickTime = elapsed;
	local now = GetTime();

	-- переносим новые таймеры, добавленные прошлым кадром/колбэками
	for i = 1, #waiting do
		active[#active + 1] = waiting[i];
		waiting[i] = nil;
	end

	local i = 1;
	while i <= #active do
		local t = active[i];
		if now >= t.at then
			-- удаляем swap-remove, потом вызываем (колбэк может добавить новые таймеры в waiting)
			active[i] = active[#active];
			active[#active] = nil;

			local ok, err = pcall(t.fn);
			if not ok then
				geterrorhandler()(err);
			end
		else
			i = i + 1;
		end
	end

	if #active == 0 and #waiting == 0 then
		self:Hide();
	end
end);

function C_Timer.After(duration, callback)
	if type(callback) ~= "function" then
		error("Usage: C_Timer.After(seconds, func)", 2);
	end
	duration = tonumber(duration) or 0;
	waiting[#waiting + 1] = { at = GetTime() + duration, fn = callback };
	driver:Show();
end

-- GetTickTime (нужен Util.lua / FrameDeltaLerp)
if not GetTickTime then
	function GetTickTime()
		return tickTime > 0 and tickTime or (1 / math.max(GetFramerate(), 1));
	end
end

---------------------------------------------------------------------------
-- C_TimerAugment.lua (7.3.5)
---------------------------------------------------------------------------
local TickerPrototype = {};
local TickerMetatable = {
	__index = TickerPrototype,
	__metatable = true,
};

-- Если callback бросит ошибку, тикер остановится (как в оригинале).
function C_Timer.NewTicker(duration, callback, iterations)
	local ticker = setmetatable({}, TickerMetatable);
	ticker._remainingIterations = iterations;
	ticker._callback = function()
		if ( not ticker._cancelled ) then
			callback(ticker);

			if ( not ticker._cancelled ) then
				if ( ticker._remainingIterations ) then
					ticker._remainingIterations = ticker._remainingIterations - 1;
				end
				if ( not ticker._remainingIterations or ticker._remainingIterations > 0 ) then
					C_Timer.After(duration, ticker._callback);
				end
			end
		end
	end;

	C_Timer.After(duration, ticker._callback);
	return ticker;
end

function C_Timer.NewTimer(duration, callback)
	return C_Timer.NewTicker(duration, callback, 1);
end

function TickerPrototype:Cancel()
	self._cancelled = true;
end

function TickerPrototype:IsCancelled()
	return self._cancelled;
end
