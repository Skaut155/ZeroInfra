"""Structural smoke tests for string transformations using representative upstream excerpts.
These tests do not substitute compiling the full firmware on an actual checkout.
"""
import importlib.util
from pathlib import Path
p=Path(__file__).resolve().parents[1]/'tools'/'apply.py'
spec=importlib.util.spec_from_file_location('emergency_apply',p)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

queue_h='''#pragma once
#include "MeshTypes.h"
#include <queue>
class MeshPacketQueue
{
    size_t maxLen;
    std::vector<meshtastic_MeshPacket *> queue;
  public:
    explicit MeshPacketQueue(size_t _maxLen);
};
'''
transformed=m.queue_header(queue_h)
assert 'struct EmergencyQueueStats' in transformed and 'queuedAt' in transformed

queue_cpp='''#include "MeshPacketQueue.h"
MeshPacketQueue::MeshPacketQueue(size_t _maxLen) : maxLen(_maxLen) {}
bool MeshPacketQueue::enqueue(meshtastic_MeshPacket *p, bool *dropped)
{
    // no space - try to replace a lower priority packet in the queue
    if (queue.size() >= maxLen) {
        bool replaced = replaceLowerPriorityPacket(p);
        if (!replaced) {
            LOG_WARN("full");
        }
    }
    auto it = std::upper_bound(queue.begin(), queue.end(), p, CompareMeshPacketFunc);
    queue.insert(it, p); // Insert packet at the found position
    return true;
}
meshtastic_MeshPacket *MeshPacketQueue::dequeue()
{
    auto *p = queue.front();
    queue.erase(queue.begin()); // Remove the highest-priority packet
    return p;
}
meshtastic_MeshPacket *MeshPacketQueue::getFront()
{
    auto *p = queue.front();
    return p;
}
meshtastic_MeshPacket *MeshPacketQueue::remove()
{
            queue.erase(it);
            return p;
}
bool MeshPacketQueue::replaceLowerPriorityPacket(meshtastic_MeshPacket *p)
{
        queue.pop_back();
        packetPool.release(backPacket);
            queue.erase(it);
            packetPool.release(refPacket);
            queue.pop_back();
            packetPool.release(backPacket);
}
'''
try:
    transformed=m.queue_impl(queue_cpp)
except RuntimeError as ex:
    raise AssertionError(f'queue_cpp anchor not found in mocked fixture: {ex}')
assert transformed.count('queuedAt.pop_back();')==2
assert 'queuedAt.erase(queuedAt.begin() + (it - queue.begin()));' in transformed
assert 'const size_t i = bestReadyIndex();' in transformed

radio_h='''    MeshPacketQueue txQueue = MeshPacketQueue(MAX_TX_QUEUE);'''
assert 'emergencyCadBusy' in m.radio_header(radio_h)
radio_cpp='''                        LOG_DEBUG_RADIO("CAD busy");
                        LOG_DEBUG_RADIO("CAD free");
            lastTxStart = Time::getMillis();
            printPacket("Started Tx", txp);
void RadioLibInterface::periodicRadioMaintenance()
{'''
assert 'EMG_TXQ' in m.radio_impl(radio_cpp)

router_cpp='''#include "Router.h"
        coerceCoordinatePacketToPositionChannel(p);
void Router::enqueueReceivedMessage(meshtastic_MeshPacket *p)
{
        if (old_p) {
            printPacket("fromRadioQ full, drop oldest!", old_p);
    // Nasty hack because our threading is primitive.  interfaces shouldn't need to know about routers FIXME
    setReceivedMessage();'''
assert 'EMERGENCY_APP_PRIORITY' in m.router_impl(router_cpp)
reliable_cpp='''#include "ReliableRouter.h"
    if (p->want_ack) {
        DEBUG_HEAP_BEFORE;
            LOG_DEBUG("Received a %s for 0x%08x, stopping retransmissions", ackId ? "ACK" : "NAK", ackId);'''
assert 'EMG_RELIABLE' in m.reliable_impl(reliable_cpp)
assert '[env:tbeam-emergency]' in m.platformio('[platformio]\nextra_configs = variants/*/*.ini\n')
print('OK: coincidencia de anclajes representativos en todos los archivos editados')
