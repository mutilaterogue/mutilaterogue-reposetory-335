#pragma once

// Draw distance beyond the 3.3.5a (12340) client's limits: ground clutter (grass) and small doodads.
//  * groundEffectDist  - the CVar's callback 0x78DB10 rejects anything above 140 (fld [0x9E8CFC] at 0x78DB2D)
//  * environmentDetail - the doodad distance multiplier; its callback 0x78DC60 rejects anything above 1.5
//    (fld [0xA41B18] at 0x78DC7D, a constant shared with many other functions, so only this read is moved)
// Both reads are pointed at our own maximums.

class DrawDistance
{
public:
    static void ApplyPatches();

private:
    DrawDistance() = delete;
    ~DrawDistance() = delete;
};
