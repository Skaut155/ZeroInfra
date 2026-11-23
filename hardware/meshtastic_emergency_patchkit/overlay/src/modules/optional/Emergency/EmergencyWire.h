#pragma once
// Experimental application payload on PRIVATE_APP=256. No modification to LoRa frame format.
// This file intentionally only uses standard C++ so it can be tested on the host.
#include <stddef.h>
#include <stdint.h>

namespace EmergencyWire {
static constexpr size_t HEADER_SIZE = 20;
static constexpr size_t MAX_TEXT_SIZE = 160;
static constexpr uint8_t VERSION = 1;
enum class Kind : uint8_t { Alert = 1, Receipt = 2, Resolved = 3, Fetch = 4, Replay = 5 };
struct Message {
    Kind kind;
    uint8_t severity;
    uint8_t flags;             // bit 0: request application receipt; only valid on direct alerts
    uint32_t id;               // application ID, distinct from MeshPacket.id
    uint32_t expiresUnix;      // 0 disables absolute expiration; verify only with trustworthy RTC
    uint32_t originNode;       // original alert issuer, not necessarily the sender of a receipt
    const uint8_t *text;
    size_t textSize;
};
inline uint32_t load32(const uint8_t *b)
{
    return uint32_t(b[0]) | (uint32_t(b[1]) << 8) | (uint32_t(b[2]) << 16) | (uint32_t(b[3]) << 24);
}
inline void store32(uint8_t *b, uint32_t x)
{
    b[0] = uint8_t(x); b[1] = uint8_t(x >> 8); b[2] = uint8_t(x >> 16); b[3] = uint8_t(x >> 24);
}
inline bool parse(const uint8_t *data, size_t size, Message &m)
{
    if (!data || size < HEADER_SIZE || size > HEADER_SIZE + MAX_TEXT_SIZE) return false;
    if (data[0] != 'E' || data[1] != 'M' || data[2] != 'G' || data[3] != '1') return false;
    if (data[4] != VERSION || data[5] < 1 || data[5] > 5 || data[6] > 3 || (data[7] & ~uint8_t(1))) return false;
    const Kind kind = static_cast<Kind>(data[5]);
    if (kind != Kind::Alert && data[7] != 0) return false;
    if ((kind == Kind::Receipt || kind == Kind::Fetch) && size != HEADER_SIZE) return false;
    m.kind = kind; m.severity = data[6]; m.flags = data[7];
    m.id = load32(data+8); m.expiresUnix = load32(data+12); m.originNode = load32(data+16);
    m.text = data + HEADER_SIZE; m.textSize = size - HEADER_SIZE;
    return ((kind == Kind::Fetch) || (m.id != 0 && m.originNode != 0)) &&
           ((kind != Kind::Alert && kind != Kind::Replay) || (m.textSize > 0 && m.severity > 0));
}
inline size_t serialize(uint8_t *out, size_t capacity, const Message &m)
{
    if (!out || m.textSize > MAX_TEXT_SIZE || capacity < HEADER_SIZE + m.textSize || ((m.id == 0 || m.originNode == 0) && m.kind != Kind::Fetch) ||
        m.severity > 3 || (m.flags & ~uint8_t(1)) ||
        (m.kind != Kind::Alert && m.kind != Kind::Receipt && m.kind != Kind::Resolved &&
         m.kind != Kind::Fetch && m.kind != Kind::Replay) ||
        ((m.kind == Kind::Alert || m.kind == Kind::Replay) && (m.textSize == 0 || m.severity == 0)) ||
        (m.kind != Kind::Alert && m.flags != 0) ||
        ((m.kind == Kind::Receipt || m.kind == Kind::Fetch) && m.textSize != 0) || (m.textSize && !m.text)) return 0;
    out[0]='E'; out[1]='M'; out[2]='G'; out[3]='1'; out[4]=VERSION;
    out[5]=static_cast<uint8_t>(m.kind); out[6]=m.severity; out[7]=m.flags;
    store32(out+8,m.id); store32(out+12,m.expiresUnix); store32(out+16,m.originNode);
    for(size_t i=0;i<m.textSize;++i) out[HEADER_SIZE+i]=m.text[i];
    return HEADER_SIZE + m.textSize;
}
}
