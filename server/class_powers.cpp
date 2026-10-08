/*
 * Class powers of Cataclysm on 3.3.5a: Soul Shards (warlock), Eclipse (balance druid), Holy Power (paladin).
 *
 * The 3.3.5a unit has no field for them (UNIT_FIELD_POWER1..7 are mana .. runic power), so the server keeps them
 * here and sends them to the client by AddonComm: "CLASS_POWER" : type : value : max : direction. The client
 * (ClassPower/ClassPower.lua) answers UnitPower / UnitPowerMax with them and updates the bars.
 * Only the player's own values are sent (the bars are the player frame's).
 *
 * Types (the client's SPELL_POWER_*): 7 Soul Shards, 8 Eclipse, 9 Holy Power.
 *
 * Holy Power (0 .. 5, as retail)
 *   +1: Crusader Strike, Holy Shock, Hammer of the Righteous (when they hit)
 *   cost 3 (not cast without it): Shield of the Righteous, Divine Storm
 * Eclipse (-100 lunar .. +100 solar; a balance druid: Moonkin Form known)
 *   Wrath: -13 while heading to the moon, Starfire: +20 while heading to the sun (either way at the start)
 *   at -100: Lunar Eclipse (48518), then toward the sun; at +100: Solar Eclipse (48517), then toward the moon
 *   out of combat it drifts back to 0 (10 a second) and the direction is free again
 * Soul Shards (0 .. 3)
 *   +1: a target dying under your Drain Soul; out of combat +1 every 5 seconds up to 3
 *   cost 1 (not cast without it): Soul Fire, Shadowburn, Death Coil
 */

#include "ScriptMgr.h"
#include "Custom\AddonComm\AddonComm.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "SpellAuraEffects.h"
#include "SpellInfo.h"
#include "SpellScript.h"
#include <unordered_map>

namespace
{
    enum ClassPowerType : uint32
    {
        POWER_SOUL_SHARDS   = 7,
        POWER_ECLIPSE       = 8,
        POWER_HOLY_POWER    = 9,
    };

    enum ClassPowerSpells : uint32
    {
        SPELL_MOONKIN_FORM          = 24858,
        SPELL_SOLAR_ECLIPSE         = 48517,
        SPELL_LUNAR_ECLIPSE         = 48518,
    };

    constexpr int32 HOLY_POWER_MAX      = 5;        // retail's five sockets
    constexpr int32 HOLY_POWER_SPEND    = 3;        // a spender takes up to this (retail's)
    constexpr int32 SOUL_SHARDS_MAX     = 3;
    constexpr int32 ECLIPSE_MAX         = 100;
    constexpr int32 ECLIPSE_WRATH       = 13;
    constexpr int32 ECLIPSE_STARFIRE    = 20;
    constexpr int32 ECLIPSE_DRIFT       = 10;       // a second, out of combat
    constexpr uint32 SHARD_REGEN_MS     = 5000;     // out of combat
    constexpr int32 SOUL_SHARD_COST     = 1;

    // the direction the client shows: "none", "sun", "moon"
    enum EclipseDirection : uint8 { ECLIPSE_NONE, ECLIPSE_SUN, ECLIPSE_MOON };
    char const* DirectionName(uint8 direction)
    {
        return direction == ECLIPSE_SUN ? "sun" : (direction == ECLIPSE_MOON ? "moon" : "none");
    }

    struct ClassPowerState
    {
        int32 holyPower = 0;
        int32 soulShards = SOUL_SHARDS_MAX;
        int32 eclipse = 0;
        uint8 direction = ECLIPSE_NONE;
        uint32 shardTimer = 0;
        uint32 driftTimer = 0;
    };

    std::unordered_map<ObjectGuid::LowType, ClassPowerState> s_states;

    ClassPowerState& State(Player* player)
    {
        return s_states[player->GetGUID().GetCounter()];
    }

    bool IsBalanceDruid(Player* player)
    {
        return player->GetClass() == CLASS_DRUID && player->HasSpell(SPELL_MOONKIN_FORM);
    }

    void SendPower(Player* player, uint32 type)
    {
        ClassPowerState& state = State(player);
        switch (type)
        {
            case POWER_HOLY_POWER:
                sAddonComm->Send(player, std::string("CLASS_POWER"), type, state.holyPower, HOLY_POWER_MAX, "none");
                break;
            case POWER_SOUL_SHARDS:
                sAddonComm->Send(player, std::string("CLASS_POWER"), type, state.soulShards, SOUL_SHARDS_MAX, "none");
                break;
            case POWER_ECLIPSE:
                sAddonComm->Send(player, std::string("CLASS_POWER"), type, state.eclipse, ECLIPSE_MAX, DirectionName(state.direction));
                break;
            default:
                break;
        }
    }

    // a spell refused for want of the power: the client says why (UIErrorsFrame)
    void SendPowerError(Player* player, uint32 type)
    {
        sAddonComm->Send(player, std::string("CLASS_POWER_ERROR"), type);
    }

    // the power of the player's class (0: none)
    uint32 ClassPowerOf(Player* player)
    {
        switch (player->GetClass())
        {
            case CLASS_PALADIN: return POWER_HOLY_POWER;
            case CLASS_WARLOCK: return POWER_SOUL_SHARDS;
            case CLASS_DRUID:   return IsBalanceDruid(player) ? POWER_ECLIPSE : 0;
            default:            return 0;
        }
    }

    void SendAll(Player* player)
    {
        if (uint32 type = ClassPowerOf(player))
            SendPower(player, type);
    }

    void AddHolyPower(Player* player, int32 amount)
    {
        ClassPowerState& state = State(player);
        int32 value = std::max(0, std::min(HOLY_POWER_MAX, state.holyPower + amount));
        if (value == state.holyPower)
            return;
        state.holyPower = value;
        SendPower(player, POWER_HOLY_POWER);
    }

    void AddSoulShards(Player* player, int32 amount)
    {
        ClassPowerState& state = State(player);
        int32 value = std::max(0, std::min(SOUL_SHARDS_MAX, state.soulShards + amount));
        if (value == state.soulShards)
            return;
        state.soulShards = value;
        SendPower(player, POWER_SOUL_SHARDS);
    }

    // a balance spell moved the bar: toward the moon (negative) or the sun (positive)
    void MoveEclipse(Player* player, int32 amount)
    {
        ClassPowerState& state = State(player);
        if ((amount < 0 && state.direction == ECLIPSE_SUN) || (amount > 0 && state.direction == ECLIPSE_MOON))
            return;     // heading the other way: this spell doesn't move it
        state.eclipse = std::max(-ECLIPSE_MAX, std::min(ECLIPSE_MAX, state.eclipse + amount));
        if (state.direction == ECLIPSE_NONE)
            state.direction = amount < 0 ? ECLIPSE_MOON : ECLIPSE_SUN;
        if (state.eclipse <= -ECLIPSE_MAX)
        {
            player->CastSpell(player, SPELL_LUNAR_ECLIPSE, true);
            state.direction = ECLIPSE_SUN;
        }
        else if (state.eclipse >= ECLIPSE_MAX)
        {
            player->CastSpell(player, SPELL_SOLAR_ECLIPSE, true);
            state.direction = ECLIPSE_MOON;
        }
        SendPower(player, POWER_ECLIPSE);
    }
}

// ---------------------------------------------------------------- Holy Power
// Crusader Strike, Holy Shock, Hammer of the Righteous: +1 Holy Power on a hit
class spell_class_power_holy_generator : public SpellScript
{
    PrepareSpellScript(spell_class_power_holy_generator);

    void HandleHit()
    {
        if (Player* player = GetCaster() ? GetCaster()->ToPlayer() : nullptr)
            if (!_done)
            {
                _done = true;       // once a cast (Hammer of the Righteous hits several targets)
                AddHolyPower(player, 1);
            }
    }

    void Register() override
    {
        OnHit += SpellHitFn(spell_class_power_holy_generator::HandleHit);
    }

    bool _done = false;
};

// Shield of the Righteous, Divine Storm: cost 3 Holy Power - not cast without it
class spell_class_power_holy_spender : public SpellScript
{
    PrepareSpellScript(spell_class_power_holy_spender);

    SpellCastResult CheckCast()
    {
        Player* player = GetCaster() ? GetCaster()->ToPlayer() : nullptr;
        if (player && State(player).holyPower < HOLY_POWER_SPEND)
        {
            SendPowerError(player, POWER_HOLY_POWER);
            return SPELL_FAILED_DONT_REPORT;
        }
        return SPELL_CAST_OK;
    }

    void HandleCast()
    {
        if (Player* player = GetCaster() ? GetCaster()->ToPlayer() : nullptr)
            AddHolyPower(player, -HOLY_POWER_SPEND);
    }

    void Register() override
    {
        OnCheckCast += SpellCheckCastFn(spell_class_power_holy_spender::CheckCast);
        BeforeCast += SpellCastFn(spell_class_power_holy_spender::HandleCast);
    }
};

// ---------------------------------------------------------------- Eclipse
// Wrath: toward the moon
class spell_class_power_eclipse_wrath : public SpellScript
{
    PrepareSpellScript(spell_class_power_eclipse_wrath);

    void HandleHit()
    {
        Player* player = GetCaster() ? GetCaster()->ToPlayer() : nullptr;
        if (player && IsBalanceDruid(player))
            MoveEclipse(player, -ECLIPSE_WRATH);
    }

    void Register() override
    {
        OnHit += SpellHitFn(spell_class_power_eclipse_wrath::HandleHit);
    }
};

// Starfire: toward the sun
class spell_class_power_eclipse_starfire : public SpellScript
{
    PrepareSpellScript(spell_class_power_eclipse_starfire);

    void HandleHit()
    {
        Player* player = GetCaster() ? GetCaster()->ToPlayer() : nullptr;
        if (player && IsBalanceDruid(player))
            MoveEclipse(player, ECLIPSE_STARFIRE);
    }

    void Register() override
    {
        OnHit += SpellHitFn(spell_class_power_eclipse_starfire::HandleHit);
    }
};

// ---------------------------------------------------------------- Soul Shards
// Drain Soul: the target dying under it gives a shard
class spell_class_power_drain_soul : public AuraScript
{
    PrepareAuraScript(spell_class_power_drain_soul);

    void HandleRemove(AuraEffect const* /*aurEff*/, AuraEffectHandleModes /*mode*/)
    {
        if (GetTargetApplication()->GetRemoveMode() != AURA_REMOVE_BY_DEATH)
            return;
        if (Player* player = GetCaster() ? GetCaster()->ToPlayer() : nullptr)
            AddSoulShards(player, 1);
    }

    void Register() override
    {
        AfterEffectRemove += AuraEffectRemoveFn(spell_class_power_drain_soul::HandleRemove, EFFECT_0, SPELL_AURA_PERIODIC_DAMAGE, AURA_EFFECT_HANDLE_REAL);
    }
};

// Soul Fire, Shadowburn, Death Coil: cost 1 Soul Shard - not cast without it
class spell_class_power_shard_spender : public SpellScript
{
    PrepareSpellScript(spell_class_power_shard_spender);

    SpellCastResult CheckCast()
    {
        Player* player = GetCaster() ? GetCaster()->ToPlayer() : nullptr;
        if (player && State(player).soulShards < SOUL_SHARD_COST)
        {
            SendPowerError(player, POWER_SOUL_SHARDS);
            return SPELL_FAILED_DONT_REPORT;
        }
        return SPELL_CAST_OK;
    }

    void HandleCast()
    {
        if (Player* player = GetCaster() ? GetCaster()->ToPlayer() : nullptr)
            AddSoulShards(player, -SOUL_SHARD_COST);
    }

    void Register() override
    {
        OnCheckCast += SpellCheckCastFn(spell_class_power_shard_spender::CheckCast);
        BeforeCast += SpellCastFn(spell_class_power_shard_spender::HandleCast);
    }
};

// ---------------------------------------------------------------- the players
class class_powers_player : public PlayerScript
{
public:
    class_powers_player() : PlayerScript("class_powers_player")
    {
        sAddonComm->Register(std::string("CLASS_POWER_GET"), [](Player* player, std::vector<std::string> const&)
        {
            SendAll(player);
        });
    }

    void OnLogin(Player* player, bool /*firstLogin*/) override
    {
        State(player) = ClassPowerState();
        SendAll(player);
    }

    void OnLogout(Player* player) override
    {
        s_states.erase(player->GetGUID().GetCounter());
    }
};

// out of combat: the shards come back, the eclipse drifts to 0
class class_powers_world : public WorldScript
{
public:
    class_powers_world() : WorldScript("class_powers_world") { }

    void OnUpdate(uint32 diff) override
    {
        for (auto& entry : s_states)
        {
            Player* player = ObjectAccessor::FindConnectedPlayer(ObjectGuid::Create<HighGuid::Player>(entry.first));
            if (!player || !player->IsInWorld() || player->IsInCombat())
                continue;
            ClassPowerState& state = entry.second;

            if (player->GetClass() == CLASS_WARLOCK && state.soulShards < SOUL_SHARDS_MAX)
            {
                state.shardTimer += diff;
                if (state.shardTimer >= SHARD_REGEN_MS)
                {
                    state.shardTimer = 0;
                    AddSoulShards(player, 1);
                }
            }

            if (player->GetClass() == CLASS_DRUID && (state.eclipse != 0 || state.direction != ECLIPSE_NONE))
            {
                state.driftTimer += diff;
                if (state.driftTimer >= 1000)
                {
                    state.driftTimer = 0;
                    if (state.eclipse > 0)
                        state.eclipse = std::max(0, state.eclipse - ECLIPSE_DRIFT);
                    else if (state.eclipse < 0)
                        state.eclipse = std::min(0, state.eclipse + ECLIPSE_DRIFT);
                    if (state.eclipse == 0)
                        state.direction = ECLIPSE_NONE;
                    SendPower(player, POWER_ECLIPSE);
                }
            }
        }
    }
};

void AddSC_class_powers()
{
    RegisterSpellScript(spell_class_power_holy_generator);
    RegisterSpellScript(spell_class_power_holy_spender);
    RegisterSpellScript(spell_class_power_eclipse_wrath);
    RegisterSpellScript(spell_class_power_eclipse_starfire);
    RegisterSpellScript(spell_class_power_drain_soul);
    RegisterSpellScript(spell_class_power_shard_spender);
    new class_powers_player();
    new class_powers_world();
}
