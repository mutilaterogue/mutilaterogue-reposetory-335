-- Система меню в стиле ретейла для 3.3.5a.
-- Ретейловая реализация построена на Compositor, intrinsic-фреймах и пулах регионов,
-- чего в 3.3.5 нет. Здесь повторён её API (описания элементов, MenuUtil, DropdownButton),
-- а отрисовка своя: фрейм меню с кнопками на ретейловых атласах common-dropdown-*.

Menu = Menu or {};
MenuUtil = MenuUtil or {};

local ELEMENT_HEIGHT = 20;
local DIVIDER_HEIGHT = 13;
local MENU_PADDING_X = 12;
local MENU_PADDING_Y = 10;
local MIN_MENU_WIDTH = 100;

---------------------------------------------------------------------------
-- описание элемента
---------------------------------------------------------------------------
local ElementDescriptionMixin = {};
ElementDescriptionMixin.__index = ElementDescriptionMixin;

local function CreateDescription(elementType)
	local description = setmetatable({}, ElementDescriptionMixin);
	description.elementType = elementType;
	description.children = {};
	return description;
end

function ElementDescriptionMixin:Insert(description)
	table.insert(self.children, description);
	return description;
end

function ElementDescriptionMixin:EnumerateElementDescriptions()
	return ipairs(self.children);
end

function ElementDescriptionMixin:HasElements()
	return #self.children > 0;
end

function ElementDescriptionMixin:GetElementType()
	return self.elementType;
end

function ElementDescriptionMixin:IsRadio()
	return self.elementType == "radio";
end

function ElementDescriptionMixin:IsSelected()
	if self.isSelected then
		return self.isSelected(self.data) and true or false;
	end
	return false;
end

function ElementDescriptionMixin:SetSelected(value)
	if self.setSelected then
		self.setSelected(self.data, value);
	end
end

function ElementDescriptionMixin:CanSelect()
	return self.isSelected ~= nil;
end

function ElementDescriptionMixin:IsSelectionIgnored()
	return self.selectionIgnored == true;
end

function ElementDescriptionMixin:SetTooltip(initializer)
	self.tooltipInitializer = initializer;
end

function ElementDescriptionMixin:AddInitializer(initializer)
	self.initializer = initializer;
end

function ElementDescriptionMixin:SetMinimumWidth(width)
	self.minimumWidth = width;
end

function ElementDescriptionMixin:GetMinimumWidth()
	return self.minimumWidth;
end

-- вставки, как в MenuUtil: rootDescription:CreateButton(...) и прочие
function ElementDescriptionMixin:CreateTitle(text, color)
	return self:Insert(MenuUtil.CreateTitle(text, color));
end

function ElementDescriptionMixin:CreateButton(text, callback, data)
	return self:Insert(MenuUtil.CreateButton(text, callback, data));
end

function ElementDescriptionMixin:CreateCheckbox(text, isSelected, setSelected, data)
	return self:Insert(MenuUtil.CreateCheckbox(text, isSelected, setSelected, data));
end

function ElementDescriptionMixin:CreateRadio(text, isSelected, setSelected, data)
	return self:Insert(MenuUtil.CreateRadio(text, isSelected, setSelected, data));
end

-- подменю: кнопка, у которой есть вложенные элементы
function ElementDescriptionMixin:CreateSubmenu(text)
	local description = CreateDescription("submenu");
	description.text = text;
	return self:Insert(description);
end

function ElementDescriptionMixin:HasSubmenu()
	return self.elementType == "submenu" and self:HasElements();
end

function ElementDescriptionMixin:CreateDivider()
	return self:Insert(MenuUtil.CreateDivider());
end

function ElementDescriptionMixin:CreateSpacer(extent)
	return self:Insert(MenuUtil.CreateSpacer(extent));
end

---------------------------------------------------------------------------
-- MenuUtil
---------------------------------------------------------------------------
function MenuUtil.CreateRootMenuDescription()
	return CreateDescription("root");
end

function MenuUtil.SetElementText(description, text)
	description.text = text;
end

function MenuUtil.GetElementText(description)
	return description.text;
end

function MenuUtil.CreateTitle(text, color)
	local description = CreateDescription("title");
	description.text = text;
	description.color = color or NORMAL_FONT_COLOR;
	description.selectionIgnored = true;
	return description;
end

function MenuUtil.CreateButton(text, callback, data)
	local description = CreateDescription("button");
	description.text = text;
	description.callback = callback;
	description.data = data;
	return description;
end

function MenuUtil.CreateCheckbox(text, isSelected, setSelected, data)
	local description = CreateDescription("checkbox");
	description.text = text;
	description.isSelected = isSelected;
	description.setSelected = setSelected;
	description.data = data;
	return description;
end

function MenuUtil.CreateRadio(text, isSelected, setSelected, data)
	local description = CreateDescription("radio");
	description.text = text;
	description.isSelected = isSelected;
	description.setSelected = setSelected;
	description.data = data;
	return description;
end

function MenuUtil.CreateDivider()
	local description = CreateDescription("divider");
	description.selectionIgnored = true;
	return description;
end

function MenuUtil.CreateSpacer(extent)
	local description = CreateDescription("spacer");
	description.extent = extent or 8;
	description.selectionIgnored = true;
	return description;
end

function MenuUtil.TraverseMenu(description, op)
	if not description then
		return false;
	end

	for _, child in description:EnumerateElementDescriptions() do
		if op(child) then
			return true;
		end
		if MenuUtil.TraverseMenu(child, op) then
			return true;
		end
	end

	return false;
end

function MenuUtil.GetSelections(description)
	local selections = {};
	MenuUtil.TraverseMenu(description, function(child)
		if not child:IsSelectionIgnored() and child:IsSelected() then
			table.insert(selections, child);
		end
	end);
	return selections;
end

function Menu.PopulateDescription(generator, owner, rootDescription)
	generator(owner, rootDescription);
end

