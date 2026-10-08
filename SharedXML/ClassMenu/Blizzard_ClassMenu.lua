-- Blizzard_ClassMenu (retail) for 3.3.5.
-- There are no specializations in 3.3.5: the menu is always the class list (excludeSpecs),
-- specID stays UNSPECIFIED_SPEC_FILTER. The dropdown text is set here, because the 3.3.5 menu
-- port has no SetSelectionText / EnableRegenerateOnResponse.

UNSPECIFIED_CLASS_FILTER = 0;
UNSPECIFIED_SPEC_FILTER = 0;

ClassMenu = {};

local function GetClassLabel(classID)
	if not classID or classID == UNSPECIFIED_CLASS_FILTER then
		return ALL_CLASSES;
	end
	local classInfo = C_CreatureInfo.GetClassInfo(classID);
	if not classInfo then
		return ALL_CLASSES;
	end
	return HEIRLOOMS_CLASS_FILTER_FORMAT:format(ClassMenu_GetClassColorStr(classInfo.classFile), classInfo.className);
end

ClassMenu.GetClassLabel = GetClassLabel;

function ClassMenu.InitClassSpecDropdown(dropdown, getClassFilter, getSpecFilter, setClassAndSpecFilter, excludeSpecs, excludeAllSpecOption)
	local function UpdateText()
		if dropdown.SetText then
			dropdown:SetText(GetClassLabel(getClassFilter()));
		end
	end

	local function CreateData(classID, specID)
		return { classID = classID, specID = specID };
	end

	local function IsClassSelected(data)
		return getClassFilter() == data.classID;
	end

	local function SetSelected(data)
		setClassAndSpecFilter(data.classID, data.specID);
		UpdateText();
	end

	dropdown:SetupMenu(function(owner, rootDescription)
		if rootDescription.SetTag then
			rootDescription:SetTag("MENU_CLASS_FILTER");
		end

		rootDescription:CreateRadio(ALL_CLASSES, IsClassSelected, SetSelected, CreateData(UNSPECIFIED_CLASS_FILTER, UNSPECIFIED_SPEC_FILTER));

		for index = 1, GetNumClasses() do
			local _, _, classID = GetClassInfo(index);
			if classID then
				rootDescription:CreateRadio(GetClassLabel(classID), IsClassSelected, SetSelected, CreateData(classID, UNSPECIFIED_SPEC_FILTER));
			end
		end
	end);

	UpdateText();
end
