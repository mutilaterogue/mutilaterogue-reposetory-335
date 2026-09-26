-- Трансмогрификация: строки ретейла (GlobalStrings 12.x, ruRU). Если строка уже есть в GlobalStrings клиента - берётся она.
-- Сервер присылает ошибки именами этих строк (TMOG_RESULT : ok : имя : itemId).

local function S(name, text)
	if _G[name] == nil then
		_G[name] = text;
	end
end

S("TRANSMOGRIFY", "Трансмогрификация");
S("TRANSMOGRIFICATION", "Трансмогрификация");
S("TRANSMOGRIFIED", "Предмет трансмогрифицирован в:\n%s");
S("TRANSMOGRIFIED_HEADER", "Трансмогрификация:");
S("TRANSMOGRIFY_CLEAR_ALL_PENDING", "Отменить все незаконченные изменения.");
S("TRANSMOGRIFY_INVALID_CANNOT_USE", "Вы не можете использовать предмет этой модели.");
S("TRANSMOGRIFY_INVALID_DESTINATION", "Этот предмет нельзя трансмогрифицировать.");
S("TRANSMOGRIFY_INVALID_ITEM_TYPE", "Предметы этого типа нельзя трансмогрифицировать.");
S("TRANSMOGRIFY_INVALID_LEGENDARY", "Легендарные предметы нельзя трансмогрифицировать.");
S("TRANSMOGRIFY_INVALID_MISMATCH", "Данная модель не подходит для предмета этого типа.");
S("TRANSMOGRIFY_INVALID_NO_ITEM", "В этой ячейке нет предмета экипировки.");
S("TRANSMOGRIFY_LOSE_REFUND", "После трансмогрификации этот предмет нельзя будет вернуть торговцу.\nХотите продолжить?");
S("TRANSMOGRIFY_LOSE_TRADE", "После трансмогрификации этот предмет нельзя будет передать другому игроку или выставить на аукцион.\nХотите продолжить?");
S("TRANSMOGRIFY_STYLE_UNCOLLECTED", "У вас еще нет этой модели.");
S("TRANSMOGRIFY_TOOLTIP_APPEARANCE_KNOWN", "У вас уже есть такая модель.");
S("TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN", "У вас еще нет такой модели.");
S("TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNUSABLE", "Данная модель предмета недоступна для вашего персонажа.");
S("TRANSMOGRIFY_TOOLTIP_REVERT", "Отменить изменения");

S("ERR_TRANSMOGRIFY_CANT_EQUIP", "Вы не можете использовать внешний вид предмета, который вы не можете надеть.");
S("ERR_TRANSMOGRIFY_INVALID_DESTINATION", "Предмет \"%s\" нельзя трансмогрифицировать.");
S("ERR_TRANSMOGRIFY_INVALID_ITEM_TYPE", "Нельзя применить внешний вид этого предмета.");
S("ERR_TRANSMOGRIFY_INVALID_SOURCE", "Вы не можете использовать внешний вид этого предмета.");
S("ERR_TRANSMOGRIFY_LEGENDARY", "Вы не можете трансмогрифицировать легендарный предмет или использовать его внешний вид.");
S("ERR_TRANSMOGRIFY_MISMATCH", "При трансмогрификации можно применить только внешний вид предмета того же типа и подходящего для той же ячейки.");
S("ERR_TRANSMOGRIFY_NOT_SOULBOUND", "Предмет \"%s\" нельзя трансмогрифицировать, поскольку он не привязан к этому персонажу.");
S("ERR_TRANSMOGRIFY_SAME_APPEARANCE", "Предмет \"%s\" уже имеет такой вид.");
S("ERR_TRANSMOGRIFY_SAME_ITEM", "Предмет уже имеет выбранный вами вид.");
S("ERR_TRANSMOG_OUTFIT_SLOT_CANNOT_AFFORD", "У вас недостаточно средств.");
S("ERR_TRANSMOG_PURCHASE_FAILURE", "Ошибка при покупке. Повторите попытку позже.");
S("ERR_TRANSMOG_SET_ALREADY_KNOWN", "В вашей коллекции уже есть все модели.");
-- своя строка: окно открыто не у трансмогрификатора (REQUIRE_NPC на сервере)
S("TRANSMOG_ERR_NEED_NPC", "Подойдите к трансмогрификатору.");

S("TRANSMOG_TAB_ITEMS", "Предметы");
S("TRANSMOG_TAB_SETS", "Наборы");
S("TRANSMOG_TAB_CUSTOM_SETS", "Свои комплекты");
S("TRANSMOG_TAB_SITUATIONS", "Ситуации");
S("TRANSMOG_COLLECTED", "Полученные");
S("TRANSMOG_NOT_COLLECTED", "Не полученные");
S("TRANSMOG_SOURCE_1", "Добыча с босса");
S("TRANSMOG_SOURCE_2", "Задания");
S("TRANSMOG_SOURCE_3", "Торговец");
S("TRANSMOG_SOURCE_4", "Случайная добыча");
S("TRANSMOG_SOURCE_5", "Достижение");
S("TRANSMOG_SOURCE_6", "Профессия");
S("TRANSMOG_SOURCE_7", "Торговая лавка");

S("TRANSMOG_SHOW_EQUIPPED_GEAR", "Удалить выбранные трансмогрификации");
S("TRANSMOG_SLOT_DISPLAY_TYPE_EQUIPPED", "Показать надетое снаряжение");
S("TRANSMOG_SLOT_DISPLAY_TYPE_EQUIPPED_TOOLTIP", "После выбора этого наряда предметы в ячейке будут отображаться в изначальном виде.");
S("TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED", "Игнорировать ячейку");
S("TRANSMOG_SLOT_DISPLAY_TYPE_UNASSIGNED_TOOLTIP", "После выбора этого наряда внешний вид предметов в ячейке не будет меняться.");
S("TRANSMOG_SLOT_WARNING_NOTHING_EQUIPPED", "В этой ячейке нет предмета экипировки, который можно трансмогрифицировать.");
S("TRANSMOG_SLOT_WARNING_INVALID_EQUIPPED_DESTINATION_ITEM", "Надетый предмет в этой ячейке нельзя трансмогрифицировать.");
S("TRANSMOG_NO_VALID_ITEMS_EQUIPPED", "Не надето подходящих предметов.");
S("TRANSMOG_SHEATHE_WEAPON_TOOLTIP", "Достать/убрать оружие");
S("TRANSMOG_PENDING_CHANGES", "Вы не сохранили изменения наряда. После выхода все несохраненные изменения будут удалены.");

S("TRANSMOG_SAVE_OUTFIT", "Сохранить наряд");
S("TRANSMOG_SAVE_OUTFIT_TOOLTIP", "Сохранить и применить изменения");
S("TRANSMOG_SAVE_OUTFIT_CANNOT_AFFORD_TOOLTIP", "Недостаточно средств для сохранения");
S("TRANSMOG_PURCHASE_OUTFIT_SLOT", "Купить ячейку для наряда");
S("TRANSMOG_PURCHASE_OUTFIT_SLOT_TOOLTIP_DISABLED", "Нельзя открыть больше %d |4ячейки:ячеек:ячеек; для нарядов.");
S("TRANSMOG_EDIT_OUTFIT_SLOT", "Изменить название/значок");
S("TRANSMOG_OUTFIT_SLOT_POPUP_TEXT", "Введите название наряда (до 16 символов):");
S("TRANSMOG_OUTFIT_NAME_DEFAULT", "Снаряжение");
S("TRANSMOG_OUTFIT_NEW", "Новое снаряжение");
S("TRANSMOG_OUTFIT_NONE", "Нет снаряжений");
S("TRANSMOG_OUTFIT_DELETE", "Удалить снаряжение");
S("TRANSMOG_OUTFIT_CONFIRM_DELETE", "Вы уверены, что хотите удалить снаряжение \"%s\"?");
S("TRANSMOG_OUTFIT_ALREADY_EXISTS", "Снаряжение с таким названием уже существует.");
S("TRANSMOG_OUTFIT_INVALID_NAME", "Данное название недоступно. Выберите другое и попробуйте снова.");
S("TRANSMOG_OUTFIT_ALL_INVALID_APPEARANCES", "Вы не можете сохранить это снаряжение, так как ни одна из моделей предметов недоступна для трансмогрифиции вашему персонажу.");
S("TRANSMOG_OUTFIT_SOME_INVALID_APPEARANCES", "Для этого снаряжения не будут сохранены одна или более моделей предметов, так как они недоступны для трансмогрифиции вашему персонажу.");
S("TRANSMOG_OUTFITS_HELPTIP", "Создавайте комплекты снаряжения, заменяющие внешний вид используемого оружия и доспехов.\n\nДобавляйте эти комплекты на панель управления, чтобы выбирать их вручную или настроить автоматическую смену наряда в определенных ситуациях.");

S("TRANSMOG_SETS_NONE", "У вас нет комплектов внешнего вида");
S("TRANSMOG_SET_COMPLETE", "Полный");
S("TRANSMOG_SET_INCOMPLETE", "Не завершен");
S("TRANSMOG_SET_COMPLETION_FORMAT", "(%s/%s)");
S("TRANSMOG_SET_PARTIALLY_KNOWN", "Вам уже доступны несколько моделей, получаемых за счет этого комплекта.");

S("TRANSMOG_CUSTOM_SET_NEW", "Новый свой комплект");
S("TRANSMOG_CUSTOM_SET_NAME", "Введите название комплекта:");
S("TRANSMOG_CUSTOM_SET_NAME_DEFAULT", "Свой комплект");
S("TRANSMOG_CUSTOM_SETS_NONE", "У вас нет своих комплектов");
S("TRANSMOG_CUSTOM_SET_RENAME", "Переименовать");
S("TRANSMOG_CUSTOM_SET_DELETE", "Удалить");
S("TRANSMOG_CUSTOM_SET_REPLACE", "Заменить на текущую модель");
S("TRANSMOG_CUSTOM_SET_CONFIRM_DELETE", "Удалить свой комплект \"%s\"?");
S("TRANSMOG_CUSTOM_SET_ALREADY_EXISTS", "Это название уже используется для другого комплекта.");
S("TRANSMOG_CUSTOM_SET_ALL_INVALID_APPEARANCES", "Вы не можете сохранить этот комплект, так как ни одна из моделей предметов недоступна для трансмогрифиции вашему персонажу.");
S("TRANSMOG_CUSTOM_SET_SOME_INVALID_APPEARANCES", "Для этого комплекта не будет сохранена ни одна модель, так как они недоступны для трансмогрифиции вашему персонажу.");
S("TRANSMOG_CUSTOM_SET_NEW_TOOLTIP_DISABLED", "Добавить модель для создания своего комплекта");
S("TRANSMOG_CUSTOM_SET_NEW_TOOLTIP_DISABLED_MAX_COUNT", "Достигнуто максимальное количество своих комплектов");

S("TRANSMOG_SITUATIONS_DESCRIPTION", "Выберите из списка ситуации, в которых вы будете автоматически надевать этот наряд. Должны быть выполнены все указанные условия!\n\nЕсли подходят несколько нарядов, один из них выбирается случайным образом.");
S("TRANSMOG_SITUATIONS_ENABLED", "Ситуации включены");
S("TRANSMOG_SITUATIONS_DEFAULTS", "По умолчанию");
S("TRANSMOG_SITUATIONS_APPLY", "Применить изменения");
S("TRANSMOG_SITUATIONS_APPLY_DISABLED_TOOLTIP", "Сначала нужно выбрать подходящий вариант");
S("TRANSMOG_SITUATIONS_UNDO", "Отменить незаконченные изменения");
S("TRANSMOG_SITUATIONS_NO_VALID_OPTIONS", "Не выбрано ни одного варианта");
-- 3.3.5: ситуаций из TransmogSituation.db2 нет, свой набор условий (transmog_outfits.cpp)
S("TRANSMOG_SITUATIONS_SELECT_OUTFIT", "Выберите наряд в списке слева, чтобы настроить ситуации.");
S("TRANSMOG_SITUATION_LOCATION", "Местность");
S("TRANSMOG_SITUATION_MOVEMENT", "Передвижение");
S("TRANSMOG_SITUATION_COMBAT", "Бой");
S("TRANSMOG_SITUATION_ANY", "Любая ситуация");
S("TRANSMOG_SITUATION_LOCATION_1", "Город или таверна");
S("TRANSMOG_SITUATION_LOCATION_2", "Открытый мир");
S("TRANSMOG_SITUATION_LOCATION_3", "Подземелье");
S("TRANSMOG_SITUATION_LOCATION_4", "Рейд");
S("TRANSMOG_SITUATION_LOCATION_5", "Поле боя или арена");
S("TRANSMOG_SITUATION_MOVEMENT_1", "Верхом");
S("TRANSMOG_SITUATION_MOVEMENT_2", "Пешком");
S("TRANSMOG_SITUATION_COMBAT_1", "В бою");
S("TRANSMOG_SITUATION_COMBAT_2", "Вне боя");
