#include "Emergency.h"
#ifndef EMERGENCY_ENABLE_MODULE
#define EMERGENCY_ENABLE_MODULE 0
#endif
#if EMERGENCY_ENABLE_MODULE
#include "EmergencyConfig.h"
#include "EmergencyWire.h"
#include "mesh/SinglePortModule.h"
#include "mesh/MeshService.h"
#include "mesh/NodeDB.h"
#include "mesh/Router.h"
#include "gps/RTC.h"
#include "UptimeClock.h"
#include <string.h>

namespace {
struct SeenAlert { uint32_t origin = 0; uint32_t id = 0; uint32_t observedAt = 0; };
struct StoredAlert {
    uint8_t frame[EmergencyWire::HEADER_SIZE + EmergencyWire::MAX_TEXT_SIZE] = {};
    uint16_t size = 0;
    uint32_t storedAt = 0;
    uint32_t origin = 0;
    uint32_t id = 0;
    uint32_t expiresUnix = 0;
};

class EmergencyModule : public SinglePortModule
{
    SeenAlert history[EMERGENCY_HISTORY_SLOTS] = {};
    size_t nextSlot = 0;
    uint32_t lastReceiptMs = 0;
    uint32_t lastFetchReplyMs = 0;
    StoredAlert stored[EMERGENCY_STORED_ALERTS] = {};
    size_t storedNext = 0;

    bool authorized(uint32_t from) const
    {
        for (uint32_t node : EMERGENCY_AUTHORIZED_ORIGINS) {
            if (node != 0 && from == node) return true;
        }
        return false;
    }
    bool isDuplicate(uint32_t origin, uint32_t id)
    {
        const uint32_t now = Time::getMillis();
        for (const auto &record : history) {
            if (record.origin == origin && record.id == id && uint32_t(now - record.observedAt) < EMERGENCY_CACHE_MS)
                return true;
        }
        history[nextSlot] = {origin, id, now};
        nextSlot = (nextSlot + 1) % EMERGENCY_HISTORY_SLOTS;
        return false;
    }
    void storeAlert(const meshtastic_MeshPacket &rx, const EmergencyWire::Message &alert)
    {
        if (rx.decoded.payload.size > sizeof(stored[0].frame)) return;
        StoredAlert &slot = stored[storedNext];
        memcpy(slot.frame, rx.decoded.payload.bytes, rx.decoded.payload.size);
        slot.size = uint16_t(rx.decoded.payload.size);
        slot.storedAt = Time::getMillis();
        slot.origin = alert.originNode;
        slot.id = alert.id;
        slot.expiresUnix = alert.expiresUnix;
        storedNext = (storedNext + 1) % EMERGENCY_STORED_ALERTS;
    }
    void sendReplay(const meshtastic_MeshPacket &rx, const EmergencyWire::Message &request)
    {
        // Explicit unicast FETCH only. No unsolicited replay and no broadcast response.
        if (rx.to != nodeDB->getNodeNum() || rx.pki_encrypted) return;
        const uint32_t now = Time::getMillis();
        if (lastFetchReplyMs && uint32_t(now - lastFetchReplyMs) < EMERGENCY_FETCH_COOLDOWN_MS) return;
        for (size_t offset = 0; offset < EMERGENCY_STORED_ALERTS; ++offset) {
            const size_t index = (storedNext + EMERGENCY_STORED_ALERTS - 1 - offset) % EMERGENCY_STORED_ALERTS;
            const StoredAlert &slot = stored[index];
            if (!slot.size || uint32_t(now - slot.storedAt) >= EMERGENCY_CACHE_MS) continue;
            if (request.originNode && request.originNode != slot.origin) continue;
            if (request.id && request.id != slot.id) continue;
            if (slot.expiresUnix && getRTCQuality() >= RTCQualityFromNet &&
                getValidTime(RTCQualityFromNet) > slot.expiresUnix) continue;
            auto *p = allocDataPacket();
            if (!p) return;
            EmergencyWire::Message original = {};
            if (!EmergencyWire::parse(slot.frame, slot.size, original)) { packetPool.release(p); return; }
            original.kind = EmergencyWire::Kind::Replay;
            original.flags = 0;
            const size_t n = EmergencyWire::serialize(p->decoded.payload.bytes, sizeof(p->decoded.payload.bytes), original);
            if (!n) { packetPool.release(p); return; }
            p->decoded.payload.size = n;
            p->to = getFrom(&rx);
            p->channel = rx.channel;
            p->priority = meshtastic_MeshPacket_Priority_HIGH;
            p->want_ack = false;
            lastFetchReplyMs = Time::skipZero(now);
            service->sendToMesh(p);
            LOG_INFO("EMG_STORE_REPLAY,origin=%08x,id=%08x,to=%08x", slot.origin, slot.id, getFrom(&rx));
            return; // one bounded response per request
        }
    }
    void sendReceipt(const meshtastic_MeshPacket &rx, const EmergencyWire::Message &alert)
    {
#if EMERGENCY_ENABLE_RECEIPTS
        // Only reply to directed, authorized, channel-encrypted app alerts. Never ACK a broadcast.
        if (rx.to != nodeDB->getNodeNum() || rx.pki_encrypted || !(alert.flags & 1)) return;
        const uint32_t now = Time::getMillis();
        if (lastReceiptMs && uint32_t(now - lastReceiptMs) < EMERGENCY_RECEIPT_COOLDOWN_MS) return;
        auto *packet = allocDataPacket();
        if (!packet) return;
        EmergencyWire::Message receipt = {EmergencyWire::Kind::Receipt, 0, 0, alert.id, alert.expiresUnix,
                                          alert.originNode, nullptr, 0};
        const size_t size = EmergencyWire::serialize(packet->decoded.payload.bytes,
                                                    sizeof(packet->decoded.payload.bytes), receipt);
        if (!size) { packetPool.release(packet); return; }
        packet->decoded.payload.size = size;
        packet->to = rx.from;
        packet->channel = rx.channel;
        packet->priority = meshtastic_MeshPacket_Priority_HIGH; // protocol ACK remains higher
        packet->want_ack = false;                                // avoid acknowledgement storms
        lastReceiptMs = Time::skipZero(now);
        service->sendToMesh(packet); // ownership transferred
#endif
    }

  public:
    EmergencyModule() : SinglePortModule("emergency", meshtastic_PortNum_PRIVATE_APP) {}

  protected:
    ProcessMessage handleReceived(const meshtastic_MeshPacket &mp) override
    {
        if (mp.which_payload_variant != meshtastic_MeshPacket_decoded_tag) return ProcessMessage::CONTINUE;
        EmergencyWire::Message msg = {};
        if (!EmergencyWire::parse(mp.decoded.payload.bytes, mp.decoded.payload.size, msg)) return ProcessMessage::CONTINUE;
        const uint32_t from = getFrom(&mp);
        // A receipt can be sent by another node but still refers to the original alert origin.
        if ((msg.kind == EmergencyWire::Kind::Alert || msg.kind == EmergencyWire::Kind::Resolved) &&
            msg.originNode != from) return ProcessMessage::CONTINUE;
        if (msg.kind == EmergencyWire::Kind::Replay && !authorized(msg.originNode)) return ProcessMessage::CONTINUE;
        if (!authorized(from)) {
            LOG_WARN("EMG_APP_REJECT,unauthorized_from=%08x,id=%08x", from, msg.id);
            return ProcessMessage::CONTINUE;
        }
        if (msg.expiresUnix != 0 && getRTCQuality() >= RTCQualityFromNet &&
            getValidTime(RTCQualityFromNet) > msg.expiresUnix) {
            LOG_INFO("EMG_APP_EXPIRED,from=%08x,id=%08x", from, msg.id);
            return ProcessMessage::CONTINUE;
        }
        if (msg.kind == EmergencyWire::Kind::Fetch) {
            sendReplay(mp, msg);
            return ProcessMessage::CONTINUE;
        }
        // An alert and its delayed replay represent ONE unique application alert.
        const uint32_t kindCode = (msg.kind == EmergencyWire::Kind::Replay) ? 1U :
                                  uint32_t(static_cast<uint8_t>(msg.kind));
        const uint32_t keySender = msg.kind == EmergencyWire::Kind::Receipt ? from : msg.originNode;
        if (isDuplicate(keySender, msg.id ^ (kindCode << 24))) return ProcessMessage::CONTINUE;
        LOG_INFO("EMG_APP_RX,kind=%u,origin=%08x,from=%08x,id=%08x,severity=%u",
                 unsigned(static_cast<uint8_t>(msg.kind)), msg.originNode, from, msg.id, unsigned(msg.severity));
        if (msg.kind == EmergencyWire::Kind::Alert) {
            storeAlert(mp, msg); // bounded, RAM-only, no automatic retransmission
            sendReceipt(mp, msg);
        }
        // Preserve usual client delivery, including legacy clients that handle PRIVATE_APP themselves.
        return ProcessMessage::CONTINUE;
    }
};
} // namespace

void setupEmergency() { new EmergencyModule(); }

#else
void setupEmergency() {} // Optional module is absent in the stock env:tbeam build.
#endif
