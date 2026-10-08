-- ============================================================
--  The guild emblem (Cataclysm's SetLargeGuildTabardTextures) for 3.3.5a: the colors from GuildColorBackground /
--  GuildColorBorder / GuildColorEmblem.dbc (Cataclysm's), the emblems from Interface\GuildFrame\GuildEmblemsLG_01
--  (1024 x 1024, 16 columns of 64 x 64). The guild's own from the server ("GUILD_EMBLEM", guild_achievements.cpp).
--  API: GuildEmblem_Set(emblemTexture, backgroundTexture, borderTexture, emblem), GetGuildEmblemInfo() -> emblem
--  (emblem: { style, color, borderStyle, borderColor, background }, nil: no design).
-- ============================================================

GUILD_COLOR_BACKGROUND = { [0]={255,32,136}, [1]={189,0,91}, [2]={158,0,54}, [3]={255,137,27}, [4]={225,69,0}, [5]={177,0,46}, [6]={255,179,23}, [7]={246,135,0}, [8]={174,75,0}, [9]={255,252,20}, [10]={243,202,0}, [11]={196,155,0}, [12]={255,255,20}, [13]={216,221,0}, [14]={166,172,0}, [15]={227,246,24}, [16]={183,192,3}, [17]={142,151,0}, [18]={188,246,27}, [19]={136,186,3}, [20]={88,128,0}, [21]={30,255,104}, [22]={4,195,71}, [23]={0,130,15}, [24]={30,247,193}, [25]={4,183,143}, [26]={0,144,97}, [27]={33,220,255}, [28]={0,157,197}, [29]={0,99,145}, [30]={77,142,218}, [31]={44,106,174}, [32]={0,53,130}, [33]={211,74,200}, [34]={173,41,172}, [35]={134,15,154}, [36]={255,56,250}, [37]={201,0,195}, [38]={155,0,166}, [39]={255,31,191}, [40]={211,0,135}, [41]={163,0,104}, [42]={197,129,50}, [43]={135,85,19}, [44]={79,35,0}, [45]={35,35,35}, [46]={100,100,100}, [47]={180,187,168}, [48]={215,221,203}, [49]={255,255,255}, [50]={252,104,145} };
GUILD_COLOR_BORDER = { [0]={103,0,33}, [1]={103,35,0}, [2]={103,69,0}, [3]={103,86,0}, [4]={99,148,0}, [5]={99,163,0}, [6]={99,179,0}, [7]={0,103,31}, [8]={0,142,144}, [9]={0,103,147}, [10]={0,49,124}, [11]={109,0,119}, [12]={123,0,103}, [13]={84,55,10}, [14]={255,255,255}, [15]={15,20,21}, [16]={249,204,48} };
GUILD_COLOR_EMBLEM = { [0]={103,0,33}, [1]={103,35,0}, [2]={103,69,0}, [3]={103,86,0}, [4]={99,103,0}, [5]={81,103,0}, [6]={55,103,0}, [7]={0,103,31}, [8]={0,103,87}, [9]={0,72,103}, [10]={9,42,93}, [11]={86,9,93}, [12]={93,9,79}, [13]={84,55,10}, [14]={177,184,177}, [15]={16,21,23}, [16]={223,165,90} };

local EMBLEM_SIZE, EMBLEM_COLUMNS = 64 / 1024, 16;
local NO_DESIGN = { 0.2245, 0.2088, 0.1794 };

local ownEmblem;
local callbacks = {};

function GuildEmblem_RegisterCallback(func)
	tinsert(callbacks, func);
end

-- an emblem from five numbers (-1 / nil: no design)
function GuildEmblem_Make(style, color, borderStyle, borderColor, background)
	style = tonumber(style);
	if ( not style or style < 0 ) then
		return nil;
	end
	return { style = style, color = tonumber(color) or 0, borderStyle = tonumber(borderStyle) or 0,
		borderColor = tonumber(borderColor) or 0, background = tonumber(background) or 0 };
end

local function Tint(texture, colors, index)
	if ( not texture ) then
		return;
	end
	local c = colors[index or 0];
	if ( c ) then
		texture:SetVertexColor(c[1] / 255, c[2] / 255, c[3] / 255);
	else
		texture:SetVertexColor(1, 1, 1);
	end
end

function GuildEmblem_Set(emblemTexture, backgroundTexture, borderTexture, emblem)
	if ( not emblem ) then
		if ( backgroundTexture ) then
			backgroundTexture:SetVertexColor(NO_DESIGN[1], NO_DESIGN[2], NO_DESIGN[3]);
		end
		if ( borderTexture ) then
			borderTexture:SetVertexColor(NO_DESIGN[1], NO_DESIGN[2], NO_DESIGN[3]);
		end
		if ( emblemTexture ) then
			emblemTexture:SetTexture("");
		end
		return;
	end
	Tint(backgroundTexture, GUILD_COLOR_BACKGROUND, emblem.background);
	Tint(borderTexture, GUILD_COLOR_BORDER, emblem.borderColor);
	if ( emblemTexture ) then
		emblemTexture:SetTexture("Interface\\GuildFrame\\GuildEmblemsLG_01");
		local x = mod(emblem.style, EMBLEM_COLUMNS) * EMBLEM_SIZE;
		local y = floor(emblem.style / EMBLEM_COLUMNS) * EMBLEM_SIZE;
		emblemTexture:SetTexCoord(x, x + EMBLEM_SIZE, y, y + EMBLEM_SIZE);
		Tint(emblemTexture, GUILD_COLOR_EMBLEM, emblem.color);
	end
end

function GetGuildEmblemInfo()
	return ownEmblem;
end

local function OnEmblem(...)
	ownEmblem = GuildEmblem_Make(...);
	for _, func in ipairs(callbacks) do
		func(ownEmblem);
	end
end

local registered = false;
local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_ENTERING_WORLD");
loader:RegisterEvent("PLAYER_GUILD_UPDATE");
loader:SetScript("OnEvent", function(self)
	if ( not Comm_Register ) then
		return;
	end
	if ( not registered ) then
		Comm_Register("GUILD_EMBLEM", OnEmblem);
		registered = true;
	end
	Comm_Send("GUILD_EMBLEM_GET");
end);
