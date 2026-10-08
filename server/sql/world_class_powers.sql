-- Class powers (server/class_powers.cpp): the spells' scripts. A negative id: every rank of the spell.
DELETE FROM `spell_script_names` WHERE `ScriptName` IN ('spell_class_power_holy_generator', 'spell_class_power_holy_spender',
    'spell_class_power_eclipse_wrath', 'spell_class_power_eclipse_starfire', 'spell_class_power_drain_soul',
    'spell_class_power_shard_spender');
INSERT INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES
-- Holy Power: Crusader Strike, Holy Shock (all ranks), Hammer of the Righteous
(35395,  'spell_class_power_holy_generator'),
(-20473, 'spell_class_power_holy_generator'),
(53595,  'spell_class_power_holy_generator'),
-- spent: Shield of the Righteous (all ranks), Divine Storm
(-53600, 'spell_class_power_holy_spender'),
(53385,  'spell_class_power_holy_spender'),
-- Eclipse: Wrath, Starfire (all ranks)
(-5176,  'spell_class_power_eclipse_wrath'),
(-2912,  'spell_class_power_eclipse_starfire'),
-- Soul Shards: Drain Soul (all ranks); spent: Soul Fire, Shadowburn, Death Coil (all ranks)
(-1120,  'spell_class_power_drain_soul'),
(-6353,  'spell_class_power_shard_spender'),
(-17877, 'spell_class_power_shard_spender'),
(-6789,  'spell_class_power_shard_spender');
