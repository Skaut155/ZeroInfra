#pragma once
#include <stddef.h>
#include <stdint.h>
#define LOG_WARN(...) ((void)0)
#define LOG_INFO(...) ((void)0)
enum ProcessMessage { CONTINUE=0, STOP=1 };
enum meshtastic_PortNum { meshtastic_PortNum_PRIVATE_APP=256 };
enum { meshtastic_MeshPacket_decoded_tag=3, meshtastic_MeshPacket_Priority_HIGH=100 };
struct meshtastic_Payload { uint8_t bytes[239]; size_t size=0; };
struct meshtastic_Data { meshtastic_Payload payload; uint16_t portnum=0; };
struct meshtastic_MeshPacket {
    meshtastic_Data decoded;
    uint32_t from=0, to=0, channel=0, id=0;
    uint32_t priority=0;
    int which_payload_variant=3;
    bool want_ack=false, pki_encrypted=false;
};
inline uint32_t getFrom(const meshtastic_MeshPacket *p) { return p->from; }
class SinglePortModule {
public:
    SinglePortModule(const char *, meshtastic_PortNum) {}
protected:
    meshtastic_MeshPacket* allocDataPacket() { return nullptr; }
    virtual ProcessMessage handleReceived(const meshtastic_MeshPacket &) { return CONTINUE; }
};
