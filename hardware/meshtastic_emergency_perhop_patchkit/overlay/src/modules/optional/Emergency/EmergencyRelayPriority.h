#pragma once

// Per-hop experimental QoS policy for the existing EMG1 application payload.
// Meshtastic 2.8.2 (b48e1e0). This file is deliberately side-effect-free except
// for the explicit priority assignment in promote().
//
// Include after the caller has included a Meshtastic MeshPacket declaration and
// its generated PortNum/Priority enums. The same code can be tested with stubs.
#include "EmergencyConfig.h"
#include "EmergencyWire.h"
#include <stdint.h>

namespace EmergencyRelayPriority {

inline bool authorized(uint32_t nodeNum)
{
    if (nodeNum == 0 || nodeNum == UINT32_MAX)
        return false;
    for (uint32_t allowed : EMERGENCY_AUTHORIZED_ORIGINS) {
        if (allowed != 0 && allowed == nodeNum)
            return true;
    }
    return false;
}

// readOnly eligibility. Must be called AFTER the existing Meshtastic decode and
// authentication gates: 'xeddsa_signed' is strictly local metadata set only by
// a successfully verified sender signature, not a field supplied by the peer.
// A matching NodeNum alone is intentionally insufficient for relay elevation.
template <typename Packet> inline bool eligible(const Packet &p, bool requireVerifiedSignature)
{
    if (p.which_payload_variant != meshtastic_MeshPacket_decoded_tag ||
        p.decoded.portnum != meshtastic_PortNum_PRIVATE_APP || p.pki_encrypted || !authorized(p.from))
        return false;
    if (requireVerifiedSignature && !p.xeddsa_signed)
        return false;

    EmergencyWire::Message emg = {};
    if (!EmergencyWire::parse(p.decoded.payload.bytes, p.decoded.payload.size, emg))
        return false;
    // Deliberately only original ALERT, not RECEIVE/REPLAY/FETCH/RESOLVED. Prevent
    // using a low-cost control message to jump the TX queue.
    return emg.kind == EmergencyWire::Kind::Alert &&
           emg.originNode == p.from && emg.id != 0 && emg.severity > 0;
}

template <typename Packet> inline bool promoteRelay(Packet &p)
{
    if (!eligible(p, true))
        return false;
    // Preserve all priorities above ALERT, in particular protocol ACK (120).
    // Do not touch any tx_after/backoff/hop/duty-cycle/routing fields.
    if (p.priority < meshtastic_MeshPacket_Priority_ALERT) {
        p.priority = meshtastic_MeshPacket_Priority_ALERT;
        return true;
    }
    return false;
}

template <typename Packet> inline bool promoteLocal(Packet &p, uint32_t localNodeNum)
{
    // PhoneAPI may supply from=0, which Router::send() later resolves to the
    // local NodeNum. Do not mistake that legitimate convention for an unlisted
    // sender; ALWAYS evaluate authorization against the true local NodeNum.
    if (!authorized(localNodeNum) || (p.from && p.from != localNodeNum) ||
        p.which_payload_variant != meshtastic_MeshPacket_decoded_tag ||
        p.decoded.portnum != meshtastic_PortNum_PRIVATE_APP || p.pki_encrypted)
        return false;
    EmergencyWire::Message emg = {};
    if (!EmergencyWire::parse(p.decoded.payload.bytes, p.decoded.payload.size, emg) ||
        emg.kind != EmergencyWire::Kind::Alert || emg.originNode != localNodeNum ||
        emg.id == 0 || emg.severity == 0)
        return false;
    // Originator signs subsequently in perhapsEncode(). The per-hop effect
    // still requires a successfully verified signature on every relay.
    if (p.priority < meshtastic_MeshPacket_Priority_ALERT) {
        p.priority = meshtastic_MeshPacket_Priority_ALERT;
        return true;
    }
    return false;
}

} // namespace EmergencyRelayPriority
