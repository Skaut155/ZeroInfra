#include <cstdint>
#include <cstdio>
#include <cassert>
#include <cstring>

// Lightweight stand-ins for generated Meshtastic types: exercise the REAL
// EmergencyRelayPriority.h and EMG1 parser without requiring PlatformIO.
static constexpr int meshtastic_MeshPacket_decoded_tag = 1;
static constexpr int meshtastic_MeshPacket_encrypted_tag = 2;
static constexpr int meshtastic_PortNum_PRIVATE_APP = 256;
static constexpr unsigned meshtastic_MeshPacket_Priority_DEFAULT = 64;
static constexpr unsigned meshtastic_MeshPacket_Priority_HIGH = 100;
static constexpr unsigned meshtastic_MeshPacket_Priority_ALERT = 110;
static constexpr unsigned meshtastic_MeshPacket_Priority_ACK = 120;
struct Payload { uint8_t bytes[220] = {}; size_t size = 0; };
struct Data { int portnum = meshtastic_PortNum_PRIVATE_APP; Payload payload; };
struct MockPacket {
    int which_payload_variant = meshtastic_MeshPacket_decoded_tag;
    uint32_t from = 0x1a21fd32;
    bool pki_encrypted = false;
    bool xeddsa_signed = false;
    unsigned priority = meshtastic_MeshPacket_Priority_DEFAULT;
    Data decoded;
};

// Provide a known authorized origin without altering the actual firmware's
// EmergencyConfig.h (which must be filled out for the real nodes).
#define EMERGENCY_TEST_CONFIG 1
// The test uses -I tests/stubs first so EmergencyRelayPriority.h's
// "EmergencyConfig.h" resolves to its neighboring original header; in this
// standalone build the original default list is {0}, so make a temporary
// config-file override via test fixture at test build time (see run_tests.py).
#include "EmergencyRelayPriority.h"

static MockPacket sample(EmergencyWire::Kind kind, uint32_t origin = 0x1a21fd32)
{
    MockPacket p;
    const uint8_t text[] = {'A', 'l', 'e', 'r', 't', 'a'};
    const EmergencyWire::Message m = {kind, 3, 0, 0x12345678, 0, origin, text,
        kind == EmergencyWire::Kind::Alert ? sizeof(text) : 0U};
    p.decoded.payload.size = EmergencyWire::serialize(
        p.decoded.payload.bytes, sizeof(p.decoded.payload.bytes), m);
    assert(p.decoded.payload.size != 0);
    return p;
}
int main()
{
    auto valid = sample(EmergencyWire::Kind::Alert);
    assert(EmergencyRelayPriority::authorized(valid.from));
    assert(!EmergencyRelayPriority::promoteRelay(valid)); // unsigned => no priority
    assert(valid.priority == 64);
    valid.xeddsa_signed = true; // only trusted after verify in real Router
    assert(EmergencyRelayPriority::promoteRelay(valid));
    assert(valid.priority == 110);
    assert(!EmergencyRelayPriority::promoteRelay(valid)); // no further change

    auto ack = sample(EmergencyWire::Kind::Alert);
    ack.xeddsa_signed = true; ack.priority = 120;
    assert(!EmergencyRelayPriority::promoteRelay(ack));
    assert(ack.priority == 120);

    auto other = sample(EmergencyWire::Kind::Alert);
    other.xeddsa_signed = true; other.from = 0x0badcafe;
    assert(!EmergencyRelayPriority::promoteRelay(other));
    other = sample(EmergencyWire::Kind::Alert, 0x0badcafe);
    other.xeddsa_signed = true;
    assert(!EmergencyRelayPriority::promoteRelay(other));

    auto spoof = sample(EmergencyWire::Kind::Alert, 0x0badcafe);
    spoof.xeddsa_signed = true;
    assert(!EmergencyRelayPriority::promoteRelay(spoof));

    auto malformed = sample(EmergencyWire::Kind::Alert);
    malformed.xeddsa_signed = true;
    malformed.decoded.payload.bytes[0] = 'X';
    assert(!EmergencyRelayPriority::promoteRelay(malformed));

    auto control = sample(EmergencyWire::Kind::Resolved);
    control.xeddsa_signed = true;
    assert(!EmergencyRelayPriority::promoteRelay(control));

    auto opaque = sample(EmergencyWire::Kind::Alert);
    opaque.xeddsa_signed = true;
    opaque.which_payload_variant = meshtastic_MeshPacket_encrypted_tag;
    assert(!EmergencyRelayPriority::promoteRelay(opaque));

    auto unknownPort = sample(EmergencyWire::Kind::Alert);
    unknownPort.xeddsa_signed = true;
    unknownPort.decoded.portnum = 1;
    assert(!EmergencyRelayPriority::promoteRelay(unknownPort));

    auto pki = sample(EmergencyWire::Kind::Alert);
    pki.xeddsa_signed = true;
    pki.pki_encrypted = true;
    assert(!EmergencyRelayPriority::promoteRelay(pki));

    auto local = sample(EmergencyWire::Kind::Alert);
    assert(EmergencyRelayPriority::promoteLocal(local, 0x1a21fd32));
    assert(local.priority == 110);
    local = sample(EmergencyWire::Kind::Alert);
    local.from = 0;  // PhoneAPI may leave from=0 until Router::send()
    assert(EmergencyRelayPriority::promoteLocal(local, 0x1a21fd32));
    local = sample(EmergencyWire::Kind::Alert);
    local.from = 0x11223344;
    assert(!EmergencyRelayPriority::promoteLocal(local, 0x1a21fd32));
    puts("OK: 13 per-hop priority assertions: signed allowlist only, preserve ACK, no opaque/PKI/spoof promotion");
}
