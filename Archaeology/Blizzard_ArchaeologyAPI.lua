-- Археология: API Cataclysm (GetArchaeologyRaceInfo, GetSelectedArtifactInfo, SolveArtifact ...) для 3.3.5
-- поверх данных сервера (server/archaeology.cpp). Статичные данные - ArchaeologyData.lua (Research*.dbc).
--   "ARCH_GET" -> "ARCH_STATE" : "branch/fragments/project,..." + "ARCH_HISTORY" : "project/count/firstTime,..."
--   "ARCH_SOLVE" : branch : keystones -> "ARCH_COMPLETE" : project
--   "ARCH_ERROR" : текст

local OP_GET, OP_STATE, OP_HISTORY, OP_SOLVE, OP_COMPLETE, OP_ERROR = "ARCH_GET", "ARCH_STATE", "ARCH_HISTORY", "ARCH_SOLVE", "ARCH_COMPLETE", "ARCH_ERROR";

local SKILL_ARCHAEOLOGY_NAME = "Археология";
local KEYSTONE_FRAGMENTS = 12;
local MAX_FRAGMENTS = 200;
local SKILL_ICON = "Interface\\Icons\\Trade_Archaeology";

-- строки Cata (ruRU), если их нет в GlobalStrings клиента
local function S(name, text)
	if _G[name] == nil then
		_G[name] = text;
	end
end
S("ARCHAEOLOGY", "Археология");
S("ARCHAEOLOGY_COMPLETED", "Завершенные артефакты");
S("ARCHAEOLOGY_COMMON_COMPLETED", "Обычные артефакты");
S("ARCHAEOLOGY_RARE_COMPLETED", "Редкие артефакты");
S("ARCHAEOLOGY_COMPLETION", "Собрано: %d");
S("ARCHAEOLOGY_CURRENT", "Текущие проекты");
S("ARCHAEOLOGY_NONE_COMPLETED", "Вы еще не собрали ни одного артефакта.");
S("ARCHAEOLOGY_POJECTBAR_TOOLTIP", "Собирайте фрагменты на местах раскопок, чтобы завершить артефакт.");
S("ARCHAEOLOGY_RANK_TOOLTIP", "Навык археологии повышается при сборе фрагментов на местах раскопок.");
S("ARCHAEOLOGY_TIMESTAMP", "Впервые собран:");
S("ARCHAEOLOGY_RUNE_STONES", "краеуг. камни");
S("ARCHAEOLOGY_KEYSTONE_ADD_TOOLTIP", "Щелкните, чтобы добавить |cffffffff%s|r.");
S("ARCHAEOLOGY_KEYSTONE_REMOVE_TOOLTIP", "Щелкните, чтобы убрать |cffffffff%s|r.");
S("ARCHAEOLOGY_DIG_HELP", "Места раскопок");
S("ARCHAEOLOGY_HELP", "Места раскопок отмечены на карте мира значком лопаты. Придите на место раскопок и используйте «Исследование»: телескоп укажет направление находки, а его цвет - расстояние до нее (красный - далеко, желтый - ближе, зеленый - рядом). Собранные фрагменты позволяют восстанавливать артефакты разных народов.");
S("ARCHAEOLOGY_SURVEY", "Исследование");
S("RACES", "Расы");
S("HISTORY", "История");
S("SOLVE", "Собрать");
S("SHORTDATE", "%2$d/%1$02d/%3$02d");

-- шрифты Cata, которых нет в 3.3.5 (до загрузки XML)
local function EnsureFont(name, base)
	if not _G[name] then
		local font = CreateFont(name);
		font:SetFontObject(_G[base] or GameFontNormal);
	end
end
EnsureFont("SystemFont_Med1", "GameFontNormal");
EnsureFont("SystemFont_Med3", "GameFontNormalLarge");

---------------------------------------------------------------------------
-- данные
---------------------------------------------------------------------------
local raceOrder = {};   -- индекс расы в окне -> ID ветки
for branchId in pairs(ARCHAEOLOGY_BRANCHES) do
	table.insert(raceOrder, branchId);
end
table.sort(raceOrder);

local state = {};        -- [branch] = { fragments, project }
local history = {};      -- [project] = { count, firstTime }
local historyReady = false;
local selectedRace, selectedArtifact;   -- индекс расы, индекс завершенного артефакта (или nil - текущий)
local socketed = 0;

local function Fire(event, ...)
	-- на странице завершенных ARTIFACT_UPDATE снова запрашивает историю - не зацикливаемся
	if event == "ARTIFACT_UPDATE" and ArchaeologyFrame and ArchaeologyFrame.completedPage:IsShown() then
		return;
	end
	if ArchaeologyFrame and ArchaeologyFrame_OnEvent then
		ArchaeologyFrame_OnEvent(ArchaeologyFrame, event, ...);
	end
end

local function BranchOf(raceIndex)
	return raceOrder[raceIndex];
end

-- завершенные артефакты расы: сначала редкие, затем обычные (как в Cata)
local function CompletedByRace(raceIndex)
	local branch = BranchOf(raceIndex);
	local list = {};
	for projectId, h in pairs(history) do
		local project = ARCHAEOLOGY_PROJECTS[projectId];
		if project and project.branch == branch and h.count > 0 then
			table.insert(list, projectId);
		end
	end
	table.sort(list, function(a, b)
		local pa, pb = ARCHAEOLOGY_PROJECTS[a], ARCHAEOLOGY_PROJECTS[b];
		if pa.rare ~= pb.rare then
			return pa.rare;
		end
		return a < b;
	end);
	return list;
end

local function ProjectInfo(projectId)
	local project = ARCHAEOLOGY_PROJECTS[projectId];
	if not project then
		return nil;
	end
	local branch = ARCHAEOLOGY_BRANCHES[project.branch];
	local icon = branch and branch.texture or "Interface\\Icons\\INV_Misc_QuestionMark";
	local bg = project.texture ~= "" and project.texture or nil;
	return project.name, project.description, project.rare and 1 or 0, icon, project.description, project.sockets, bg;
end

---------------------------------------------------------------------------
-- API Cataclysm
---------------------------------------------------------------------------
function Archaeology_GetSkillInfo()
	for i = 1, GetNumSkillLines() do
		local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i);
		if not isHeader and name == SKILL_ARCHAEOLOGY_NAME then
			return name, SKILL_ICON, rank, maxRank;
		end
	end
	return nil;
end

function GetArchaeologyInfo()
	return ARCHAEOLOGY;
end

function GetNumArchaeologyRaces()
	return #raceOrder;
end

-- name, texture, keystoneItemID, fragments, fragmentsRequired, maxFragments
function GetArchaeologyRaceInfo(raceIndex)
	local branchId = BranchOf(raceIndex);
	local branch = branchId and ARCHAEOLOGY_BRANCHES[branchId];
	if not branch then
		return nil;
	end
	local s = state[branchId];
	local project = s and ARCHAEOLOGY_PROJECTS[s.project];
	return branch.name, branch.texture, branch.keystone, s and s.fragments or 0, project and project.fragments or 0, MAX_FRAGMENTS;
end

-- число артефактов расы: завершенные + текущий проект
function GetNumArtifactsByRace(raceIndex)
	local branchId = BranchOf(raceIndex);
	local s = branchId and state[branchId];
	if not s then
		return 0;
	end
	return #CompletedByRace(raceIndex) + ((s.project and s.project > 0) and 1 or 0);
end

-- завершенный артефакт: name, description, rarity, icon, spellDescription, numSockets, bgTexture, firstCompletionTime, completionCount
function GetArtifactInfoByRace(raceIndex, artifactIndex)
	local projectId = CompletedByRace(raceIndex)[artifactIndex];
	if not projectId then
		return nil;
	end
	local name, description, rarity, icon, spellDescription, numSockets, bg = ProjectInfo(projectId);
	local h = history[projectId];
	return name, description, rarity, icon, spellDescription, numSockets, bg, h.firstTime, h.count;
end

function GetActiveArtifactByRace(raceIndex)
	local s = state[BranchOf(raceIndex)];
	if not s then
		return nil;
	end
	return ProjectInfo(s.project);
end

function SetSelectedArtifact(raceIndex, artifactIndex)
	if selectedRace ~= raceIndex or selectedArtifact ~= artifactIndex then
		socketed = 0;
	end
	selectedRace, selectedArtifact = raceIndex, artifactIndex;
end

function GetSelectedArtifactInfo()
	if not selectedRace then
		return nil;
	end
	if selectedArtifact then
		local name, description, rarity, icon, spellDescription, numSockets, bg = GetArtifactInfoByRace(selectedRace, selectedArtifact);
		return name, description, rarity, icon, spellDescription, numSockets, bg;
	end
	return GetActiveArtifactByRace(selectedRace);
end

-- fragments, fromKeystones, required
function GetArtifactProgress()
	local branchId = BranchOf(selectedRace);
	local s = branchId and state[branchId];
	local project = s and ARCHAEOLOGY_PROJECTS[s.project];
	if not project then
		return 0, 0, 0;
	end
	return s.fragments, socketed * KEYSTONE_FRAGMENTS, project.fragments;
end

function CanSolveArtifact()
	local base, adjust, total = GetArtifactProgress();
	return total > 0 and base + adjust >= total;
end

local function Keystone()
	local branch = ARCHAEOLOGY_BRANCHES[BranchOf(selectedRace) or 0];
	return branch and branch.keystone or 0;
end

function ItemAddedToArtifact(index)
	return index <= socketed;
end

-- краеугольный камень из сумок (не с курсора)
function SocketItemToArtifact()
	local _, _, _, _, _, numSockets = GetSelectedArtifactInfo();
	local keystone = Keystone();
	if keystone > 0 and socketed < (numSockets or 0) and GetItemCount(keystone) > socketed then
		socketed = socketed + 1;
	end
end

function RemoveItemFromArtifact()
	if socketed > 0 then
		socketed = socketed - 1;
	end
end

function SolveArtifact()
	local branchId = BranchOf(selectedRace);
	if branchId and CanSolveArtifact() and Comm_Send then
		Comm_Send(OP_SOLVE, branchId, socketed);
		socketed = 0;
	end
end

function RequestArtifactCompletionHistory()
	if Comm_Send then
		Comm_Send(OP_GET);
	end
end

function IsArtifactCompletionHistoryAvailable()
	return historyReady;
end

function CloseResearch()
	socketed = 0;
end

function ToggleArchaeologyFrame()
	if ArchaeologyFrame:IsShown() then
		HideUIPanel(ArchaeologyFrame);
	else
		ShowUIPanel(ArchaeologyFrame);
	end
end

SLASH_ARCHAEOLOGY1 = "/arch";
SLASH_ARCHAEOLOGY2 = "/археология";
SlashCmdList["ARCHAEOLOGY"] = ToggleArchaeologyFrame;

---------------------------------------------------------------------------
-- сервер
---------------------------------------------------------------------------
if Comm_Register then
	Comm_Register(OP_STATE, function(text)
		wipe(state);
		for branch, fragments, project in (text or ""):gmatch("(%d+)/(%d+)/(%d+)") do
			state[tonumber(branch)] = { fragments = tonumber(fragments), project = tonumber(project) };
		end
		Fire("ARTIFACT_UPDATE");
	end);

	Comm_Register(OP_HISTORY, function(text)
		wipe(history);
		for project, count, firstTime in (text or ""):gmatch("(%d+)/(%d+)/(%d+)") do
			history[tonumber(project)] = { count = tonumber(count), firstTime = tonumber(firstTime) };
		end
		historyReady = true;
		Fire("ARTIFACT_HISTORY_READY");
	end);

	Comm_Register(OP_COMPLETE, function(projectId)
		local name = ProjectInfo(tonumber(projectId));
		if name then
			local info = ChatTypeInfo["SYSTEM"];
			DEFAULT_CHAT_FRAME:AddMessage(("Артефакт восстановлен: %s"):format(name), info.r, info.g, info.b, info.id);
			PlaySound("igQuestListComplete");
		end
		Fire("ARTIFACT_COMPLETE", name);
	end);

	Comm_Register(OP_ERROR, function(text)
		UIErrorsFrame:AddMessage(text or "", 1.0, 0.1, 0.1, 1.0);
	end);
end

local loader = CreateFrame("Frame");
loader:RegisterEvent("PLAYER_ENTERING_WORLD");
loader:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents();
	if Comm_Send then
		Comm_Send(OP_GET);
		Comm_Send("ARCH_SITES_GET");
	end
end);
