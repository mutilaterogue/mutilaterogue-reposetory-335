-- world DB: the specialization change cast (spec_primary.cpp, SPEC_CHANGE_SPELL): put your spell id (a 2 s cast with
-- no effect of its own) here and into SPEC_CHANGE_SPELL; the change happens when the cast ends.
-- INSERT IGNORE INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES (<spell id>, 'spell_spec_change');

-- the dual spec switch (Activate Primary / Secondary Spec, 5 s): not during a keystone run - the cast does not start
-- (spell_spec_change: CheckCast; its AfterCast does nothing without a choice from the specialization tab)
INSERT IGNORE INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES
(63644, 'spell_spec_change'),
(63645, 'spell_spec_change');
