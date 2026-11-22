// Unit test of the ACTUAL installed EmergencyRelayPriority.h and EmergencyConfig.h.
// Compile with: g++ -std=c++17 -I firmware/src/modules/optional/Emergency/ tests/test_policy.cpp -o /tmp/test_policy
#include <cassert>
#include <cstdint>
#include <cstdio>

static constexpr int meshtastic_MeshPacket_decoded_tag = 1;
static constexpr int meshtastic_MeshPacket_encrypted_tag = 2;
static constexpr int meshtastic_PortNum_PRIVATE_APP = 256;
static constexpr unsigned meshtastic_MeshPacket_Priority_DEFAULT = 64;
static constexpr unsigned meshtastic_MeshPacket_Priority_ALERT = 110;
static constexpr unsigned meshtastic_MeshPacket_Priority_ACK = 120;
struct Payload { uint8_t bytes[233] = {}; size_t size = 0; };
struct Data { int portnum = 256; Payload payload; };
struct Packet {
    int which_payload_variant = meshtastic_MeshPacket_decoded_tag;
    uint32_t from = 0x0badcafe;
    bool pki_encrypted = false;
    bool xeddsa_signed = false;
    unsigned priority = meshtastic_MeshPacket_Priority_DEFAULT;
    Data decoded;
};
#include "EmergencyRelayPriority.h"

static Packet makeAlert(uint32_t origin)
{
    Packet p;
    p.from = origin;
    const uint8_t text[] = {'S','O','S'};
    EmergencyWire::Message message = {EmergencyWire::Kind::Alert, 3, 0, 0x12345678,
                                      0, origin, text, sizeof(text)};
    p.decoded.payload.size = EmergencyWire::serialize(
        p.decoded.payload.bytes, sizeof(p.decoded.payload.bytes), message);
    assert(p.decoded.payload.size != 0);
    return p;
}

int main()
{
    // Todo NodeNum válido puede originar alertas, no hay allowlist fija.
    assert(EmergencyOriginPolicy::validNodeNum(0x1a21fd32));
    assert(EmergencyOriginPolicy::validNodeNum(0x0badcafe));
    assert(!EmergencyOriginPolicy::validNodeNum(0));
    assert(!EmergencyOriginPolicy::validNodeNum(UINT32_MAX));

    auto local = makeAlert(0x0badcafe);
    assert(EmergencyRelayPriority::promoteLocal(local, 0x0badcafe));
    assert(local.priority == 110);
    auto anotherLocal = makeAlert(0x1a21fd32);
    anotherLocal.from = 0; // caso PhoneAPI
    assert(EmergencyRelayPriority::promoteLocal(anotherLocal, 0x1a21fd32));
    auto invalidLocal = makeAlert(0x0badcafe);
    assert(!EmergencyRelayPriority::promoteLocal(invalidLocal, 0));

    // Sin XEdDSA verificada NO se promociona a lo largo de la malla.
    auto unsignedRelay = makeAlert(0x0badcafe);
    assert(!EmergencyRelayPriority::promoteRelay(unsignedRelay));
    assert(unsignedRelay.priority == 64);

    auto signedRelay = makeAlert(0x0badcafe);
    signedRelay.xeddsa_signed = true;
    assert(EmergencyRelayPriority::promoteRelay(signedRelay));
    assert(signedRelay.priority == 110);
    assert(!EmergencyRelayPriority::promoteRelay(signedRelay));

    auto otherSignedRelay = makeAlert(0x1a21fd32);
    otherSignedRelay.xeddsa_signed = true;
    assert(EmergencyRelayPriority::promoteRelay(otherSignedRelay));

    auto spoofed = makeAlert(0x0badcafe);
    spoofed.from = 0x1a21fd32;
    spoofed.xeddsa_signed = true;
    assert(!EmergencyRelayPriority::promoteRelay(spoofed));

    auto opaque = makeAlert(0x0badcafe);
    opaque.which_payload_variant = meshtastic_MeshPacket_encrypted_tag;
    opaque.xeddsa_signed = true;
    assert(!EmergencyRelayPriority::promoteRelay(opaque));

    auto malformed = makeAlert(0x0badcafe);
    malformed.decoded.payload.bytes[0] = 'X';
    malformed.xeddsa_signed = true;
    assert(!EmergencyRelayPriority::promoteRelay(malformed));

    auto ack = makeAlert(0x0badcafe);
    ack.priority = 120;
    ack.xeddsa_signed = true;
    assert(!EmergencyRelayPriority::promoteRelay(ack));
    assert(ack.priority == 120);

    auto normalText = makeAlert(0x0badcafe);
    normalText.decoded.portnum = 1;
    normalText.xeddsa_signed = true;
    assert(!EmergencyRelayPriority::promoteRelay(normalText));

    puts("OK: politica OPEN-SOS + relay firmado + preservacion ACK + paquete normal");
}
