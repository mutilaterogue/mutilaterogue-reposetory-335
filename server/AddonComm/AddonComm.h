#ifndef CIRCLE_ADDON_COMM_H
#define CIRCLE_ADDON_COMM_H

#include "Player.h"
#include "WorldPacket.h"
#include "WorldSession.h"
#include "ObjectGuid.h"
#include "Opcodes.h"
#include "Log.h"
#include <functional>
#include <unordered_map>
#include <map>
#include <vector>
#include <string>
#include <sstream>
#include <cstdlib>

#define CIRCLE_PREFIX    "CIRCLE"
#define CIRCLE_SEP       ':'
#define CIRCLE_MAXBYTES  240
#define CIRCLE_MAXCHUNKS 64

enum CircleCMSG : uint32
{
    CMSG_CIRCLE_REQUEST_TALENT_TREE         = 1,
    CMSG_CIRCLE_REQUEST_CREATURE_CACHE      = 2,
    CMSG_CIRCLE_REQUEST_HEIRLOOMS           = 3,
    CMSG_CIRCLE_CREATE_HEIRLOOM             = 4,
    CMSG_CIRCLE_REQUEST_CREATURE_BY_DISPLAY = 5,
    CMSG_CIRCLE_REQUEST_TOYS                = 6,
    CMSG_CIRCLE_USE_TOY                     = 7,
};

enum CircleSMSG : uint32
{
    SMSG_CIRCLE_TALENT_TREE                 = 1,
    SMSG_CIRCLE_MASTERY_SPELL               = 2,
    SMSG_CIRCLE_HEIRLOOM_ADDED              = 3,
    SMSG_CIRCLE_HEIRLOOM_LIST               = 4,
    SMSG_CIRCLE_CREATURE_BY_DISPLAY         = 5,
    SMSG_CIRCLE_TOY_LIST                    = 6,
    SMSG_CIRCLE_TOY_ADDED                   = 7,
    SMSG_CIRCLE_TOY_COOLDOWN                = 8,
};

// Safe uint32 parse from string (replacement for atoul)
inline uint32 CommToUInt32(std::string const& str, uint32 def = 0)
{
    if (str.empty())
        return def;

    char* end = nullptr;
    unsigned long val = strtoul(str.c_str(), &end, 10);
    if (end == str.c_str() || *end != '\0')
        return def;

    return uint32(val);
}

class AddonComm
{
public:
    typedef std::function<void(Player*, std::vector<std::string> const&)> Handler;

    static AddonComm* instance()
    {
        static AddonComm inst;
        return &inst;
    }

    void Register(uint32 opcode, Handler handler) { _handlers[opcode] = handler; }

    // Parse an incoming addon whisper. Returns true if the packet was ours.
    bool HandleIncoming(Player* player, std::string const& prefix, std::string const& body);

    void OnPlayerLogout(ObjectGuid guid) { _chunks.erase(guid); }

    // Usage: Send(player, SMSG_CIRCLE_TALENT_TREE, spec, tree, active);
    template<typename... Args>
    void Send(Player* player, uint32 opcode, Args&&... args)
    {
        std::ostringstream ss;
        ss << opcode;
        AppendAll(ss, std::forward<Args>(args)...);
        SendRaw(player, opcode, ss.str());
    }

private:
    AddonComm() {}

    void SendRaw(Player* player, uint32 opcode, std::string const& payload);
    void SendPacket(Player* player, std::string const& payload);

    static void AppendAll(std::ostringstream&) {}

    template<typename T, typename... Rest>
    static void AppendAll(std::ostringstream& ss, T&& first, Rest&&... rest)
    {
        ss << CIRCLE_SEP << std::forward<T>(first);
        AppendAll(ss, std::forward<Rest>(rest)...);
    }

    static std::vector<std::string> Split(std::string const& str, char sep);

    std::unordered_map<uint32, Handler> _handlers;

    // Chunk reassembly for packets coming from the client
    struct ChunkBuffer
    {
        uint32 total = 0;
        uint32 received = 0;
        std::vector<std::string> parts;
    };

    // std::map because ObjectGuid has operator< in every 3.3.5 fork,
    // while ObjectGuid::Hash is not always present
    std::map<ObjectGuid, std::unordered_map<uint32, ChunkBuffer>> _chunks;
};

#define sAddonComm AddonComm::instance()

#endif
