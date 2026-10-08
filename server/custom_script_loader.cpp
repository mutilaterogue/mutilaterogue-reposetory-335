/*
 * This file is part of the TrinityCore Project. See AUTHORS file for Copyright information
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

// This is where scripts' loading functions should be declared:

// The name of this function should match:
// void Add${NameOfDirectory}Scripts()
void AddSC_cs_talent_tree();
void AddSC_collections_creature_cache();
void AddSC_heirloom_collection();
void AddSC_toy_collection();
void AddSC_appearance_collection();
void AddSC_transmog();
void AddSC_transmog_outfits();
void AddSC_transmog_sets();
void AddSC_transmog_illusions();
void AddSC_talent_loadouts();
void AddSC_item_scaling();
void AddSC_item_upgrade();
void AddSC_mythic_plus();
void AddSC_archaeology();
void AddSC_group_convert();
void AddSC_talent_custom();
void AddSC_spec_primary();
void AddSC_raid_finder();
void AddSC_premade_groups();
void AddSC_class_powers();
void AddSC_guild_progression();

void AddCustomScripts()
{
    AddSC_cs_talent_tree();
    AddSC_collections_creature_cache();
    AddSC_heirloom_collection();
    AddSC_toy_collection();
    AddSC_appearance_collection();
    AddSC_transmog();
    AddSC_transmog_outfits();
    AddSC_transmog_sets();
    AddSC_transmog_illusions();
    AddSC_talent_loadouts();
    AddSC_item_scaling();
    AddSC_item_upgrade();
    AddSC_mythic_plus();
    AddSC_archaeology();
    AddSC_group_convert();
    AddSC_talent_custom();
    AddSC_spec_primary();
    AddSC_raid_finder();
    AddSC_premade_groups();
    AddSC_class_powers();
    AddSC_guild_progression();
}
