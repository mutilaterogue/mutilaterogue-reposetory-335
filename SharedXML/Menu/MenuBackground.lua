-- Фон меню: нарезка через штатный NineSliceUtil (FrameXML\Utils\NineSlice.lua).
Menu = Menu or {};

-- Раскладка фона для штатного NineSliceUtil (FrameXML\Utils\NineSlice.lua).
-- Отдельных кусков под common-dropdown-bg в атласах нет, атлас цельный,
-- поэтому куски вырезаются из него координатами через setupPieceVisualsFunction.
local BACKGROUND_ATLAS = "common-dropdown-bg";
local CORNER_SIZE = 18;

local function SetupDropdownBackgroundPiece(container, piece, setupInfo, pieceLayout)
	local info = C_Texture.GetAtlasInfo(BACKGROUND_ATLAS);
	if not info then
		return;
	end

	local width = info.right - info.left;
	local height = info.bottom - info.top;

	-- доля угла внутри атласа
	local u = CORNER_SIZE / info.width;
	local v = CORNER_SIZE / info.height;

	-- какую часть атласа берёт этот кусок
	local left, right, top, bottom;
	local name = setupInfo.pieceName;

	if name == "TopLeftCorner" then
		left, right, top, bottom = 0, u, 0, v;
	elseif name == "TopRightCorner" then
		left, right, top, bottom = 1 - u, 1, 0, v;
	elseif name == "BottomLeftCorner" then
		left, right, top, bottom = 0, u, 1 - v, 1;
	elseif name == "BottomRightCorner" then
		left, right, top, bottom = 1 - u, 1, 1 - v, 1;
	elseif name == "TopEdge" then
		left, right, top, bottom = u, 1 - u, 0, v;
	elseif name == "BottomEdge" then
		left, right, top, bottom = u, 1 - u, 1 - v, 1;
	elseif name == "LeftEdge" then
		left, right, top, bottom = 0, u, v, 1 - v;
	elseif name == "RightEdge" then
		left, right, top, bottom = 1 - u, 1, v, 1 - v;
	else
		left, right, top, bottom = u, 1 - u, v, 1 - v;
	end

	piece:SetTexture(info.file or info.filename);
	piece:SetTexCoord(info.left + width * left, info.left + width * right,
		info.top + height * top, info.top + height * bottom);
	piece:SetAlpha(0.925);

	-- углы фиксированы, края тянутся только поперёк своей стороны
	if setupInfo.fn == nil or name:find("Corner") then
		piece:SetSize(CORNER_SIZE, CORNER_SIZE);
	elseif setupInfo.tileHorizontal then
		piece:SetHeight(CORNER_SIZE);
	elseif setupInfo.tileVertical then
		piece:SetWidth(CORNER_SIZE);
	end
end

-- Регистрируется лениво: Menu грузится из SharedXML раньше, чем FrameXML\Utils\NineSlice.lua
local backgroundLayout = {
	setupPieceVisualsFunction = SetupDropdownBackgroundPiece,
	TopLeftCorner = { atlas = BACKGROUND_ATLAS },
	TopRightCorner = { atlas = BACKGROUND_ATLAS },
	BottomLeftCorner = { atlas = BACKGROUND_ATLAS },
	BottomRightCorner = { atlas = BACKGROUND_ATLAS },
	TopEdge = { atlas = BACKGROUND_ATLAS },
	BottomEdge = { atlas = BACKGROUND_ATLAS },
	LeftEdge = { atlas = BACKGROUND_ATLAS },
	RightEdge = { atlas = BACKGROUND_ATLAS },
	Center = { atlas = BACKGROUND_ATLAS },
};

local MENU_BACKGROUND_LAYOUT = "CommonDropdownBackground";

-- применить фон-нарезку, если NineSliceUtil уже доступен
function Menu.ApplyBackgroundLayout(frame)
	if not NineSliceUtil then
		return false;
	end

	if not NineSliceUtil.GetLayout(MENU_BACKGROUND_LAYOUT) then
		NineSliceUtil.AddLayout(MENU_BACKGROUND_LAYOUT, backgroundLayout);
	end

	frame.layoutTextureLayer = "BACKGROUND";
	NineSliceUtil.ApplyLayoutByName(frame, MENU_BACKGROUND_LAYOUT);

	if frame.Background then
		frame.Background:Hide();
	end

	return true;
end

