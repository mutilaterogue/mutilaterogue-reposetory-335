#include "AddonComm.h"
#include "ObjectMgr.h"
#include "Chat.h"
#include <sstream>

std::vector<std::string> AddonComm::Split(std::string const& str, char sep)
{
    std::vector<std::string> out;
    std::string cur;
    for (char c : str)
    {
        if (c == sep) { out.push_back(cur); cur.clear(); }
        else cur += c;
    }
    out.push_back(cur);
    return out;
}

bool AddonComm::HandleIncoming(Player* player, std::string const& prefix, std::string const& body)
{
    if (!player || prefix != CIRCLE_PREFIX || body.empty())
        return false;

    std::vector<std::string> parts = Split(body, CIRCLE_SEP);
    if (parts.empty())
        return false;

    // Chunked packet: C : opcode : index : total : data
    if (parts[0] == "C")
    {
        if (parts.size() < 5)
            return true;

        uint32 opcode = CommToUInt32(parts[1]);
        uint32 idx = CommToUInt32(parts[2]);
        uint32 total = CommToUInt32(parts[3]);

        if (!opcode || !total || !idx || idx > total || total > CIRCLE_MAXCHUNKS)
            return true;

        ChunkBuffer& buf = _chunks[player->GetGUID()][opcode];
        if (buf.total != total)
        {
            buf.total = total;
            buf.received = 0;
            buf.parts.assign(total, std::string());
        }

        if (buf.parts[idx - 1].empty())
            ++buf.received;
        buf.parts[idx - 1] = parts[4];

        if (buf.received < total)
            return true;

        std::string full;
        for (auto const& p : buf.parts)
            full += p;

        _chunks[player->GetGUID()].erase(opcode);

        auto itr = _handlers.find(opcode);
        if (itr != _handlers.end())
            itr->second(player, Split(full, CIRCLE_SEP));

        return true;
    }

    uint32 opcode = CommToUInt32(parts[0]);

    auto itr = _handlers.find(opcode);
    if (itr == _handlers.end())
        return true; // our prefix, unknown opcode - swallow it

    std::vector<std::string> args(parts.begin() + 1, parts.end());
    itr->second(player, args);
    return true;
}

void AddonComm::SendRaw(Player* player, uint32 opcode, std::string const& payload)
{
    if (!player || !player->GetSession())
        return;

    if (payload.size() <= CIRCLE_MAXBYTES)
    {
        SendPacket(player, payload);
        return;
    }

    // Strip "opcode:" - the body is sent in chunks
    std::string head = std::to_string(opcode) + CIRCLE_SEP;
    std::string body = payload.substr(head.size());

    size_t chunkSize = CIRCLE_MAXBYTES - 24;
    uint32 total = uint32((body.size() + chunkSize - 1) / chunkSize);

    if (total > CIRCLE_MAXCHUNKS)
    {
        TC_LOG_ERROR("server", "AddonComm: payload too large for opcode %u", opcode);
        return;
    }

    for (uint32 i = 0; i < total; ++i)
    {
        std::ostringstream ss;
        ss << "C" << CIRCLE_SEP << opcode << CIRCLE_SEP << (i + 1) << CIRCLE_SEP << total
            << CIRCLE_SEP << body.substr(i * chunkSize, chunkSize);
        SendPacket(player, ss.str());
    }
}

void AddonComm::SendPacket(Player* player, std::string const& payload)
{
    // Addon whisper from the player to himself
    std::string msg = std::string(CIRCLE_PREFIX) + "\t" + payload;

    WorldPacket data(SMSG_MESSAGECHAT, 100);
    data << uint8(CHAT_MSG_WHISPER);
    data << uint32(LANG_ADDON);
    data << player->GetGUID();
    data << uint32(0);                  // flags
    data << player->GetGUID();          // receiver
    data << uint32(msg.length() + 1);
    data << msg;
    data << uint8(0);                   // chat tag

    player->GetSession()->SendPacket(&data);
}
