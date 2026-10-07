#pragma once

// Draw distance beyond the 3.3.5a (12340) client's limits, and the fog.
//  * groundEffectDist  - the CVar's callback 0x78DB10 rejects anything above 140 (fld [0x9E8CFC] at 0x78DB2D)
//  * environmentDetail - the doodad distance multiplier; its callback 0x78DC60 rejects anything above 1.5
//    (fld [0xA41B18] at 0x78DC7D, a constant shared with many other functions, so only this read is moved)
//    Both reads are pointed at our own maximums.
//  * fog (CVar fogMode: 0 the client's, 1 three times farther, 2 none):
//    - 0x7816F0, once a frame, lights the world: the zone light's result (0xD38B00: +0x90 fog start, +0x94 fog
//      end) is read by everything drawn after it. Ours goes there after it, the client's own is put back before
//      its next run (it blends the light from frame to frame)
//    - 0x834990 CM2Lighting::SetFog(color, start, end, density): the models' / map objects' own fog (interiors)

class DrawDistance
{
public:
    static void ApplyPatches();

private:
    DrawDistance() = delete;
    ~DrawDistance() = delete;
};
