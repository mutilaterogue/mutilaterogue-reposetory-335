local AtlasInfo = AtlasCache

C_Texture = {}

local CONST_ATLAS_WIDTH			= 1
local CONST_ATLAS_HEIGHT		= 2
local CONST_ATLAS_LEFT			= 3
local CONST_ATLAS_RIGHT			= 4
local CONST_ATLAS_TOP			= 5
local CONST_ATLAS_BOTTOM		= 6
local CONST_ATLAS_TILESHORIZ	= 7
local CONST_ATLAS_TILESVERT		= 8
local CONST_ATLAS_TEXTUREPATH	= 9

function C_Texture.GetAtlasInfo(atlasName)
	if type(atlasName) ~= "string" then
		error("Usage: C_Texture.GetAtlasInfo(\"atlasName\")", 2)
	end

	local atlas = AtlasInfo[atlasName]
	if not atlas then
		GMError(string.format("C_Texture.GetAtlasInfo: Atlas %s does not exist", atlasName), 2)
		return
	end

	local sliceData
	local sliceInfo = atlas.slice
	if sliceInfo then
		sliceData = {
			marginLeft = sliceInfo[1],
			marginTop = sliceInfo[2],
			marginRight = sliceInfo[3],
			marginBottom = sliceInfo[4],
			sliceMode = sliceInfo.tile and 1 or 0,
		}
	end

	return {
		width 				= atlas[CONST_ATLAS_WIDTH],
		height 				= atlas[CONST_ATLAS_HEIGHT],
		leftTexCoord 		= atlas[CONST_ATLAS_LEFT],
		rightTexCoord 		= atlas[CONST_ATLAS_RIGHT],
		topTexCoord 		= atlas[CONST_ATLAS_TOP],
		bottomTexCoord 		= atlas[CONST_ATLAS_BOTTOM],
		tilesHorizontally	= atlas[CONST_ATLAS_TILESHORIZ],
		tilesVertically 	= atlas[CONST_ATLAS_TILESVERT],
		filename 			= atlas[CONST_ATLAS_TEXTUREPATH],
		sliceData 			= sliceData,
	}
end

function C_Texture.HasAtlasInfo(atlasName)
	if type(atlasName) ~= "string" then
		error("Usage: C_Texture.GetAtlasInfo(\"atlasName\")", 2)
	end
	return AtlasInfo[atlasName] ~= nil
end

local AtlasSlicePieceOrder = {
	{ pieceName = "TopLeftCorner", point = "TOPLEFT" },
	{ pieceName = "TopRightCorner", point = "TOPRIGHT" },
	{ pieceName = "BottomLeftCorner", point = "BOTTOMLEFT" },
	{ pieceName = "BottomRightCorner", point = "BOTTOMRIGHT" },
	{ pieceName = "TopEdge", point = "TOPLEFT", relativePoint = "TOPRIGHT", relativePieces = { "TopLeftCorner", "TopRightCorner" } },
	{ pieceName = "BottomEdge", point = "BOTTOMLEFT", relativePoint = "BOTTOMRIGHT", relativePieces = { "BottomLeftCorner", "BottomRightCorner" } },
	{ pieceName = "LeftEdge", point = "TOPLEFT", relativePoint = "BOTTOMLEFT", relativePieces = { "TopLeftCorner", "BottomLeftCorner" } },
	{ pieceName = "RightEdge", point = "TOPRIGHT", relativePoint = "BOTTOMRIGHT", relativePieces = { "TopRightCorner", "BottomRightCorner" } },
	{ pieceName = "Center" },
}

local NineAtlasSlice = {
	TopLeftCorner =  function(piece, atlasInfo, pixelWidth, pixelHeight, marginLeft, marginRight, marginTop, marginBottom)
		piece:SetSize(marginLeft, marginTop)
		piece:SetTexCoord(atlasInfo.leftTexCoord, atlasInfo.leftTexCoord + pixelWidth * marginLeft, atlasInfo.topTexCoord, atlasInfo.topTexCoord + pixelHeight * marginTop)
	end,
	TopRightCorner = function(piece, atlasInfo, pixelWidth, pixelHeight, marginLeft, marginRight, marginTop, marginBottom)
		piece:SetSize(marginRight, marginTop)
		piece:SetTexCoord(atlasInfo.rightTexCoord - pixelWidth * marginRight, atlasInfo.rightTexCoord, atlasInfo.topTexCoord, atlasInfo.topTexCoord + pixelHeight * marginTop)
	end,
	BottomLeftCorner = function(piece, atlasInfo, pixelWidth, pixelHeight, marginLeft, marginRight, marginTop, marginBottom)
		piece:SetSize(marginLeft, marginBottom)
		piece:SetTexCoord(atlasInfo.leftTexCoord, atlasInfo.leftTexCoord + pixelWidth * marginLeft, atlasInfo.bottomTexCoord - pixelHeight * marginBottom, atlasInfo.bottomTexCoord)
	end,
	BottomRightCorner = function(piece, atlasInfo, pixelWidth, pixelHeight, marginLeft, marginRight, marginTop, marginBottom)
		piece:SetSize(marginRight, marginBottom)
		piece:SetTexCoord(atlasInfo.rightTexCoord - pixelWidth * marginRight, atlasInfo.rightTexCoord, atlasInfo.bottomTexCoord - pixelHeight * marginBottom, atlasInfo.bottomTexCoord)
	end,
	TopEdge = function(piece, atlasInfo, pixelWidth, pixelHeight, marginLeft, marginRight, marginTop, marginBottom)
		piece:SetHeight(marginTop)
		piece:SetTexCoord(atlasInfo.leftTexCoord + pixelWidth * marginLeft, atlasInfo.rightTexCoord - pixelWidth * marginRight, atlasInfo.topTexCoord, atlasInfo.topTexCoord + pixelHeight * marginTop)
	end,
	BottomEdge = function(piece, atlasInfo, pixelWidth, pixelHeight, marginLeft, marginRight, marginTop, marginBottom)
		piece:SetHeight(marginBottom)
		piece:SetTexCoord(atlasInfo.leftTexCoord + pixelWidth * marginLeft, atlasInfo.rightTexCoord - pixelWidth * marginRight, atlasInfo.bottomTexCoord - pixelHeight * marginBottom, atlasInfo.bottomTexCoord)
	end,
	LeftEdge = function(piece, atlasInfo, pixelWidth, pixelHeight, marginLeft, marginRight, marginTop, marginBottom)
		piece:SetWidth(marginLeft)
		piece:SetTexCoord(atlasInfo.leftTexCoord, atlasInfo.leftTexCoord + pixelWidth * marginLeft, atlasInfo.topTexCoord + pixelHeight * marginTop, atlasInfo.bottomTexCoord - pixelHeight * marginBottom)
	end,
	RightEdge = function(piece, atlasInfo, pixelWidth, pixelHeight, marginLeft, marginRight, marginTop, marginBottom)
		piece:SetWidth(marginRight)
		piece:SetTexCoord(atlasInfo.rightTexCoord - pixelWidth * marginRight, atlasInfo.rightTexCoord, atlasInfo.topTexCoord + pixelHeight * marginTop, atlasInfo.bottomTexCoord - pixelHeight * marginBottom)
	end,
	Center = function(piece, atlasInfo, pixelWidth, pixelHeight, marginLeft, marginRight, marginTop, marginBottom)
		piece:SetTexCoord(atlasInfo.leftTexCoord + pixelWidth * marginLeft, atlasInfo.rightTexCoord - pixelWidth * marginRight, atlasInfo.topTexCoord + pixelHeight * marginTop, atlasInfo.bottomTexCoord - pixelHeight * marginBottom)
	end
}

local ThreeVerticalAtlasSlice = {
	LeftEdge = function(piece, atlasInfo, pixelWidth, pixelHeight, marginLeft, marginRight, marginTop, marginBottom)
		piece:SetWidth(marginLeft)
		piece:SetTexCoord(atlasInfo.leftTexCoord, atlasInfo.leftTexCoord + pixelWidth * marginLeft, atlasInfo.topTexCoord, atlasInfo.bottomTexCoord)
	end,
	RightEdge = function(piece, atlasInfo, pixelWidth, pixelHeight, marginLeft, marginRight, marginTop, marginBottom)
		piece:SetWidth(marginRight)
		piece:SetTexCoord(atlasInfo.rightTexCoord - pixelWidth * marginRight, atlasInfo.rightTexCoord, atlasInfo.topTexCoord, atlasInfo.bottomTexCoord)
	end,
	Center = function(piece, atlasInfo, pixelWidth, pixelHeight, marginLeft, marginRight, marginTop, marginBottom)
		piece:SetTexCoord(atlasInfo.leftTexCoord + pixelWidth * marginLeft, atlasInfo.rightTexCoord - pixelWidth * marginRight, atlasInfo.topTexCoord, atlasInfo.bottomTexCoord)
	end
}

local AtlasSliceTextures = {}

local function GetAtlasSlicePiece(parent, pieceName)
	if not AtlasSliceTextures[parent] then
		AtlasSliceTextures[parent] = {}
	end

	if not AtlasSliceTextures[parent][pieceName] then
		AtlasSliceTextures[parent][pieceName] = parent:CreateTexture()
	end

	return AtlasSliceTextures[parent][pieceName]
end

local function AtlasSliceSetupPiece(piece, isShown, scale, drawLayer, alpha, r, g, b, a)
	piece:SetShown(isShown)
	piece:SetScale(scale)
	piece:SetDrawLayer(drawLayer)
	piece:SetAlpha(alpha)
	piece:SetVertexColor(r, g, b, a)
end

local function AtlasSlicePieceSetPoint(piece, pieceInfo, parent, texture, isThree)
	piece:ClearAllPoints()
	piece:SetSize(0, 0)
	piece:SetTexture("")
	piece.ignoreInLayout = true -- Ignore in LayoutFrame

	if pieceInfo.relativePieces then
		if isThree then
			piece:SetPoint(pieceInfo.point, texture)
			piece:SetPoint(pieceInfo.relativePoint, texture)
		else
			piece:SetPoint(pieceInfo.point, GetAtlasSlicePiece(parent, pieceInfo.relativePieces[1]), pieceInfo.relativePoint)
			piece:SetPoint(pieceInfo.relativePoint, GetAtlasSlicePiece(parent, pieceInfo.relativePieces[2]), pieceInfo.point)
		end
	elseif pieceInfo.point then
		piece:SetPoint(pieceInfo.point, texture, pieceInfo.point)
	else
		if isThree then
			piece:SetPoint("TOPLEFT", GetAtlasSlicePiece(parent, "LeftEdge"), "TOPRIGHT")
			piece:SetPoint("BOTTOMRIGHT", GetAtlasSlicePiece(parent, "RightEdge"), "BOTTOMLEFT")
		else
			piece:SetPoint("TOPLEFT", GetAtlasSlicePiece(parent, "TopLeftCorner"), "BOTTOMRIGHT")
			piece:SetPoint("BOTTOMRIGHT", GetAtlasSlicePiece(parent, "BottomRightCorner"), "TOPLEFT")
		end
	end
end

local frame = CreateFrame("Frame")
local textureMeta = getmetatable(frame:CreateTexture()).__index

local Show = textureMeta.Show
local Hide = textureMeta.Hide
local SetScale = textureMeta.SetScale
local SetDrawLayer = textureMeta.SetDrawLayer
local SetAlpha = textureMeta.SetAlpha
local SetVertexColor = textureMeta.SetVertexColor

local function AtlasSlicePiecesSetMT(pieces, texture)
	texture.Show = function(this)
		for _, piece in ipairs(pieces) do
			Show(piece)
		end
		Show(this)
	end
	texture.Hide = function(this)
		for _, piece in ipairs(pieces) do
			Hide(piece)
		end
		Hide(this)
	end
	texture.SetShown = function(this, shown)
		for _, piece in ipairs(pieces) do
			if shown then
				Show(piece)
			else
				Hide(piece)
			end
		end
		if shown then
			Show(this)
		else
			Hide(this)
		end
	end
	texture.SetScale = function(this, scale)
		for _, piece in ipairs(pieces) do
			SetScale(piece, scale)
		end
		SetScale(this, scale)
	end
	texture.SetDrawLayer = function(this, layer)
		for _, piece in ipairs(pieces) do
			SetDrawLayer(piece, layer)
		end
		SetDrawLayer(this, layer)
	end
	texture.SetAlpha = function(this, alpha)
		for _, piece in ipairs(pieces) do
			SetAlpha(piece, alpha)
		end
		SetAlpha(this, alpha)
	end
	texture.SetVertexColor = function(this, r, g, b, a)
		for _, piece in ipairs(pieces) do
			SetVertexColor(piece, r, g, b, a)
		end
		SetVertexColor(this, r, g, b, a)
	end
end

function SetAtlasSlice(texture, atlasName, useAtlasSize)
	local atlasInfo = C_Texture.GetAtlasInfo(atlasName, useAtlasSize)
	if not atlasInfo.sliceData then
		return texture:SetAtlas(atlasName, useAtlasSize)
	end

	local parent = texture:GetParent()

	local sliceData = atlasInfo.sliceData
	local marginLeft = sliceData.marginLeft or 0
	local marginRight = sliceData.marginRight or 0
	local marginTop = sliceData.marginTop or 0
	local marginBottom = sliceData.marginBottom or 0

	local layoutInfo
	if marginTop == 0 and marginBottom == 0 then
		layoutInfo = ThreeVerticalAtlasSlice
	else
		layoutInfo = NineAtlasSlice
	end

	if not layoutInfo then
		return texture:SetAtlas(atlasName, useAtlasSize)
	end

	local pixelWidth = (atlasInfo.rightTexCoord - atlasInfo.leftTexCoord) / atlasInfo.width
	local pixelHeight = (atlasInfo.bottomTexCoord - atlasInfo.topTexCoord) / atlasInfo.height

	texture:SetTexture("")
	if useAtlasSize then
		texture:SetSize(atlasInfo.width, atlasInfo.height)
	end

	if not texture.pieces then
		texture.pieces = {}
	else
		table.wipe(texture.pieces)
	end

	local isShown = texture:IsShown()
	local scale = texture:GetScale()
	local drawLayer = texture:GetDrawLayer()
	local alpha = texture:GetAlpha()
	local r, g, b, a = texture:GetVertexColor()

	local isThree = layoutInfo.TopLeftCorner == nil

	for _, pieceInfo in pairs(AtlasSlicePieceOrder) do
		local pieceConfig = layoutInfo[pieceInfo.pieceName]
		if pieceConfig then
			local piece = GetAtlasSlicePiece(parent, pieceInfo.pieceName)
			texture.pieces[#texture.pieces + 1] = piece
			AtlasSlicePieceSetPoint(piece, pieceInfo, parent, texture, isThree)
			piece:SetTexture(atlasInfo.filename)
			pieceConfig(piece, atlasInfo, pixelWidth, pixelHeight, marginLeft, marginRight, marginTop, marginBottom)
			AtlasSliceSetupPiece(piece, isShown, scale, drawLayer, alpha, r, g, b, a)
		end
	end

	AtlasSlicePiecesSetMT(texture.pieces, texture)
end