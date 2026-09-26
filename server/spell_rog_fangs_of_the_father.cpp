/*
 * «Клыки Отца» (легендарные кинжалы разбойника, Cataclysm 4.3) для TrinityCore 3.3.5.
 *
 * 109939 (пассивная аура предметов) - атаки ближнего боя с шансом дают 109941 «Тени Разрушителя» (+ловкость, до StackAmount).
 *        Начиная с 109939 m1 стаков каждый следующий стак с нарастающим шансом вызывает 109949 «Ярость Разрушителя»:
 *        все «Тени» снимаются, серия приёмов сразу увеличивается на 109949 s1.
 * 109949 «Ярость Разрушителя» (время действия - 109949 d): каждый завершающий приём добавляет 109950 s1 приёмов в серию.
 *
 * Шанс «Ярости»: при m1 стаках - 1 / (StackAmount - m1 + 1), на последнем стаке - 100%,
 * то есть растёт линейно от порога до максимума (как в Cata: гарантированно на последнем стаке).
 *
 * Регистрация: AddSC_spell_rog_fangs_of_the_father() в custom_script_loader.cpp,
 * spell_script_names и spell_proc - sql/world_fangs_of_the_father.sql.
 */

#include "ScriptMgr.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "SpellAuraEffects.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "SpellScript.h"
#include "Unit.h"

enum FangsOfTheFather
{
    SPELL_ROGUE_FANGS_PASSIVE        = 109939,   // пассивка кинжалов, m1 - порог стаков
    SPELL_ROGUE_SHADOWS_DESTROYER    = 109941,   // «Тени Разрушителя»: ловкость, стаки
    SPELL_ROGUE_FURY_DESTROYER       = 109949,   // «Ярость Разрушителя»: s1 приёмов в серию сразу, аура на d
    SPELL_ROGUE_FURY_FINISHER_BONUS  = 109950,   // s1 приёмов в серию после завершающего приёма
};

// 109939 - Тени Разрушителя: стаки и шанс «Ярости»
class spell_rog_fangs_of_the_father : public AuraScript
{
    PrepareAuraScript(spell_rog_fangs_of_the_father);

    bool Validate(SpellInfo const* /*spellInfo*/) override
    {
        return ValidateSpellInfo({ SPELL_ROGUE_SHADOWS_DESTROYER, SPELL_ROGUE_FURY_DESTROYER, SPELL_ROGUE_FURY_FINISHER_BONUS });
    }

    bool CheckProc(ProcEventInfo& eventInfo)
    {
        // только атаки ближнего боя, и не во время «Ярости»
        Unit* actor = eventInfo.GetActor();
        return actor && actor->GetTypeId() == TYPEID_PLAYER && !actor->HasAura(SPELL_ROGUE_FURY_DESTROYER);
    }

    void HandleProc(ProcEventInfo& eventInfo)
    {
        PreventDefaultAction();

        Unit* caster = eventInfo.GetActor();
        Unit* target = eventInfo.GetActionTarget();
        AuraEffect const* aurEff = GetEffect(EFFECT_0);
        if (!caster || !target || caster == target || !aurEff)
            return;

        caster->CastSpell(caster, SPELL_ROGUE_SHADOWS_DESTROYER, true);

        Aura* shadows = caster->GetAura(SPELL_ROGUE_SHADOWS_DESTROYER);
        if (!shadows)
            return;

        int32 threshold = std::max(1, aurEff->GetAmount());                              // 109939 m1
        int32 maxStacks = std::max<int32>(threshold, shadows->GetSpellInfo()->StackAmount); // 109941 u
        int32 stacks = shadows->GetStackAmount();
        if (stacks < threshold)
            return;

        // нарастающий шанс: 1 из (оставшихся до максимума + 1), на последнем стаке - всегда
        float chance = 100.0f / float(maxStacks - stacks + 1);
        if (!roll_chance_f(chance))
            return;

        caster->RemoveAurasDueToSpell(SPELL_ROGUE_SHADOWS_DESTROYER);
        // 109949: приёмы в серию на цель атаки + аура «Ярости» на разбойнике
        caster->CastSpell(target, SPELL_ROGUE_FURY_DESTROYER, true);
    }

    void Register() override
    {
        DoCheckProc += AuraCheckProcFn(spell_rog_fangs_of_the_father::CheckProc);
        OnProc += AuraProcFn(spell_rog_fangs_of_the_father::HandleProc);
    }
};

// 109949 - Ярость Разрушителя: завершающие приёмы увеличивают серию на 109950 s1
class spell_rog_fury_of_the_destroyer : public AuraScript
{
    PrepareAuraScript(spell_rog_fury_of_the_destroyer);

    bool Validate(SpellInfo const* /*spellInfo*/) override
    {
        return ValidateSpellInfo({ SPELL_ROGUE_FURY_FINISHER_BONUS });
    }

    bool CheckProc(ProcEventInfo& eventInfo)
    {
        SpellInfo const* spellInfo = eventInfo.GetSpellInfo();
        return spellInfo && spellInfo->NeedsComboPoints() && eventInfo.GetActionTarget();
    }

    void HandleProc(ProcEventInfo& eventInfo)
    {
        PreventDefaultAction();

        Unit* caster = eventInfo.GetActor();
        Unit* target = eventInfo.GetActionTarget();
        if (!caster || !target)
            return;

        // завершающий приём снимает серию в конце применения - добавляем приёмы уже после него
        ObjectGuid casterGuid = caster->GetGUID();
        ObjectGuid targetGuid = target->GetGUID();
        caster->m_Events.AddEventAtOffset([caster, casterGuid, targetGuid]()
        {
            if (!caster->IsInWorld() || caster->GetGUID() != casterGuid)
                return;
            if (Unit* victim = ObjectAccessor::GetUnit(*caster, targetGuid))
                if (victim->IsAlive())
                    caster->CastSpell(victim, SPELL_ROGUE_FURY_FINISHER_BONUS, true);
        }, Milliseconds(1));
    }

    void Register() override
    {
        DoCheckProc += AuraCheckProcFn(spell_rog_fury_of_the_destroyer::CheckProc);
        OnProc += AuraProcFn(spell_rog_fury_of_the_destroyer::HandleProc);
    }
};

void AddSC_spell_rog_fangs_of_the_father()
{
    RegisterSpellScript(spell_rog_fangs_of_the_father);
    RegisterSpellScript(spell_rog_fury_of_the_destroyer);
}
