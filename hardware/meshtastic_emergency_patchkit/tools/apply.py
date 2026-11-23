#!/usr/bin/env python3
"""Apply an experimental Meshtastic QoS patch to a CLEAN local checkout.
Uses checked source anchors and aborts if upstream diverges; makes no network requests.
Does NOT flash devices or change region/duty-cycle/safety rules.
"""
from __future__ import annotations
import argparse
import re
import shutil
import subprocess
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
OVERLAY = BASE / "overlay"


def sub_once(s: str, before: str, after: str, name: str) -> str:
    count = s.count(before)
    if count != 1:
        raise RuntimeError(f"{name}: se esperaba un único anclaje; coincidencias={count}: {before[:100]!r}")
    return s.replace(before, after, 1)


def prepend_once_line(s: str, line_regex: str, statement: str, name: str) -> str:
    """Inserts a statement immediately before one matching C++ line.

    Indentation is copied from the source; zero or multiple matches abort
    to avoid changing an unexpected part of the firmware.
    """
    pattern = re.compile(r"(?m)^(?P<indent>[ \t]*)(?:" + line_regex + r")[ \t]*$")
    matches = list(pattern.finditer(s))
    if len(matches) != 1:
        raise RuntimeError(
            f"{name}: se esperaba una única línea compatible; "
            f"coincidencias={len(matches)}; expresión={line_regex!r}. "
            "Comprueba la versión del firmware y el bloque correspondiente."
        )
    match = matches[0]
    return s[:match.start()] + match.group('indent') + statement + "\n" + s[match.start():]


def queue_header(s: str) -> str:
    s = sub_once(s, "#include <queue>", "#include <queue>\n#include <vector>\n#include <stdint.h>", "MeshPacketQueue.h includes")
    s = sub_once(s, "class MeshPacketQueue\n{", """struct EmergencyQueueStats {
    uint32_t accepted = 0, evicted = 0, rejected = 0, canceled = 0, dequeued = 0;
    uint32_t peakSize = 0, maxWaitMs = 0;
    uint64_t totalWaitMs = 0;
};

class MeshPacketQueue
{""", "MeshPacketQueue.h class")
    s = sub_once(s, "    std::vector<meshtastic_MeshPacket *> queue;", """    std::vector<meshtastic_MeshPacket *> queue;
    std::vector<uint32_t> queuedAt; // parallel to queue, enqueue timestamp, monotonic ms
    EmergencyQueueStats emergencyStats;
    size_t bestReadyIndex() const;""", "MeshPacketQueue.h fields")
    s = sub_once(s, "    explicit MeshPacketQueue(size_t _maxLen);", """    explicit MeshPacketQueue(size_t _maxLen);
    EmergencyQueueStats getEmergencyStats() const { return emergencyStats; }""", "MeshPacketQueue.h public")
    return s


def queue_impl(s: str) -> str:
    s = sub_once(s, '#include "MeshPacketQueue.h"', '#include "MeshPacketQueue.h"\n#include "EmergencyQueuePolicy.h"', 'MeshPacketQueue.cpp includes')
    s = sub_once(s, 'MeshPacketQueue::MeshPacketQueue(size_t _maxLen) : maxLen(_maxLen) {}', '''MeshPacketQueue::MeshPacketQueue(size_t _maxLen) : maxLen(_maxLen)
{
    queue.reserve(maxLen);
    queuedAt.reserve(maxLen);
}

size_t MeshPacketQueue::bestReadyIndex() const
{
    if (queue.empty()) return 0;
#if EMERGENCY_QUEUE_AGING
    // Delayed relays keep the original semantics and stay behind ready packets.
    if (queue.front()->tx_after) return 0;
    const uint32_t now = Time::getMillis();
    size_t best = 0;
    uint32_t high = EmergencyQueuePolicy::effective(queue[0]->priority, uint32_t(now - queuedAt[0]));
    for (size_t i = 1; i < queue.size() && !queue[i]->tx_after; ++i) {
        const uint32_t candidate = EmergencyQueuePolicy::effective(queue[i]->priority, uint32_t(now - queuedAt[i]));
        if (candidate > high) { high = candidate; best = i; }
    }
    return best;
#else
    return 0;
#endif
}''', 'MeshPacketQueue.cpp constructor')
    s = sub_once(s, 'bool MeshPacketQueue::enqueue(meshtastic_MeshPacket *p, bool *dropped)\n{\n', '''bool MeshPacketQueue::enqueue(meshtastic_MeshPacket *p, bool *dropped)
{
    fixPriority(p);
''', 'MeshPacketQueue.cpp enqueue start')
    s = sub_once(s, '        bool replaced = replaceLowerPriorityPacket(p);\n        if (!replaced) {', '''        bool replaced = replaceLowerPriorityPacket(p);
        if (replaced) ++emergencyStats.evicted;
        else ++emergencyStats.rejected;
        if (!replaced) {''', 'MeshPacketQueue.cpp fullness')
    s = sub_once(s, '''    auto it = std::upper_bound(queue.begin(), queue.end(), p, CompareMeshPacketFunc);
    queue.insert(it, p); // Insert packet at the found position
    return true;''', '''    auto it = std::upper_bound(queue.begin(), queue.end(), p, CompareMeshPacketFunc);
    const size_t pos = size_t(it - queue.begin());
    queue.insert(it, p); // keep the current Meshtastic sort rules
    queuedAt.insert(queuedAt.begin() + pos, Time::getMillis());
    ++emergencyStats.accepted;
    if (queue.size() > emergencyStats.peakSize) emergencyStats.peakSize = uint32_t(queue.size());
    return true;''', 'MeshPacketQueue.cpp enqueue insertion')
    s = sub_once(s, '''    auto *p = queue.front();
    queue.erase(queue.begin()); // Remove the highest-priority packet
    return p;''', '''    const size_t i = bestReadyIndex();
    auto *p = queue[i];
    const uint32_t wait = uint32_t(Time::getMillis() - queuedAt[i]);
    ++emergencyStats.dequeued;
    emergencyStats.totalWaitMs += wait;
    if (wait > emergencyStats.maxWaitMs) emergencyStats.maxWaitMs = wait;
    queuedAt.erase(queuedAt.begin() + i);
    queue.erase(queue.begin() + i);
    return p;''', 'MeshPacketQueue.cpp dequeue')
    s = sub_once(s, '''    auto *p = queue.front();
    return p;
}''', '''    return queue[bestReadyIndex()];
}''', 'MeshPacketQueue.cpp getFront')
    s = sub_once(s, '''            queue.erase(it);
            return p;''', '''            const size_t pos = size_t(it - queue.begin());
            queuedAt.erase(queuedAt.begin() + pos);
            queue.erase(it);
            ++emergencyStats.canceled;
            return p;''', 'MeshPacketQueue.cpp remove')
    # Two branches evict a vector-back pointer with different indentation.
    for spaces in ('        ', '            '):
        before = spaces + 'queue.pop_back();\n' + spaces + 'packetPool.release(backPacket);'
        after = spaces + 'queue.pop_back();\n' + spaces + 'queuedAt.pop_back();\n' + spaces + 'packetPool.release(backPacket);'
        s = sub_once(s, before, after, 'MeshPacketQueue.cpp back eviction')
    s = sub_once(s, '''            queue.erase(it);
            packetPool.release(refPacket);''', '''            queuedAt.erase(queuedAt.begin() + (it - queue.begin()));
            queue.erase(it);
            packetPool.release(refPacket);''', 'MeshPacketQueue.cpp middle eviction')
    return s


def radio_header(s: str) -> str:
    return sub_once(s, '    MeshPacketQueue txQueue = MeshPacketQueue(MAX_TX_QUEUE);', '''    MeshPacketQueue txQueue = MeshPacketQueue(MAX_TX_QUEUE);
    uint32_t emergencyCadBusy = 0;
    uint32_t emergencyCadFree = 0;
    uint32_t emergencyTxStarted = 0;''', 'RadioLibInterface.h txQueue')


def radio_impl(s: str) -> str:
    # Match the CAD log lines regardless of indentation or DEBUG vs DEBUG_RADIO.
    # Still require exactly one match, to avoid editing the wrong code block.
    s = prepend_once_line(s, r'LOG_DEBUG(?:_RADIO)?\(\s*"CAD busy"\s*\);',
                          '++emergencyCadBusy;', 'RadioLibInterface.cpp CAD busy')
    s = prepend_once_line(s, r'LOG_DEBUG(?:_RADIO)?\(\s*"CAD free"\s*\);',
                          '++emergencyCadFree;', 'RadioLibInterface.cpp CAD free')
    s = prepend_once_line(s, r'lastTxStart\s*=\s*Time::getMillis\(\);',
                          '++emergencyTxStarted;', 'RadioLibInterface.cpp successful TX')
    s = sub_once(s, 'void RadioLibInterface::periodicRadioMaintenance()\n{', '''void RadioLibInterface::periodicRadioMaintenance()
{
#if EMERGENCY_METRICS
    const auto emg = txQueue.getEmergencyStats();
    LOG_INFO("EMG_TXQ,accepted=%lu,evicted=%lu,rejected=%lu,canceled=%lu,dequeued=%lu,peak=%lu,wait_max_ms=%lu,wait_avg_ms=%lu,tx_started=%lu,cad_busy=%lu,cad_free=%lu",
             (unsigned long)emg.accepted, (unsigned long)emg.evicted, (unsigned long)emg.rejected,
             (unsigned long)emg.canceled, (unsigned long)emg.dequeued, (unsigned long)emg.peakSize,
             (unsigned long)emg.maxWaitMs, (unsigned long)(emg.dequeued ? emg.totalWaitMs / emg.dequeued : 0U),
             (unsigned long)emergencyTxStarted, (unsigned long)emergencyCadBusy, (unsigned long)emergencyCadFree);
#endif''', 'RadioLibInterface.cpp maintenance')
    return s


def router_impl(s: str) -> str:
    s = sub_once(s, '#include "Router.h"', '''#include "Router.h"
#if EMERGENCY_APP_PRIORITY
#include "modules/optional/Emergency/EmergencyWire.h"
#endif''', 'Router.cpp includes')
    s = sub_once(s, '        coerceCoordinatePacketToPositionChannel(p);', '''#if EMERGENCY_APP_PRIORITY
        // Priority remains local to the node. No on-air header changes and no relay priority inference.
        // A valid custom payload from this node is identified as an emergency alert.
        if (isFromUs(p) && p->which_payload_variant == meshtastic_MeshPacket_decoded_tag &&
            p->decoded.portnum == meshtastic_PortNum_PRIVATE_APP) {
            EmergencyWire::Message e = {};
            if (EmergencyWire::parse(p->decoded.payload.bytes, p->decoded.payload.size, e) &&
                e.kind == EmergencyWire::Kind::Alert && e.originNode == getNodeNum()) {
                p->priority = meshtastic_MeshPacket_Priority_ALERT;
            }
        }
#endif
        coerceCoordinatePacketToPositionChannel(p);''', 'Router.cpp local priority')
    s = sub_once(s, 'void Router::enqueueReceivedMessage(meshtastic_MeshPacket *p)\n{', '''void Router::enqueueReceivedMessage(meshtastic_MeshPacket *p)
{
#if EMERGENCY_METRICS
    static uint32_t emergencyRxEvictions = 0;
    static uint32_t emergencyRxAccepted = 0;
#endif''', 'Router.cpp RX entrance')
    s = sub_once(s, '''        if (old_p) {
            printPacket("fromRadioQ full, drop oldest!", old_p);''', '''        if (old_p) {
#if EMERGENCY_METRICS
            ++emergencyRxEvictions;
            if ((emergencyRxEvictions % 16U) == 1U)
                LOG_WARN("EMG_RXQ,drop_oldest_total=%lu", (unsigned long)emergencyRxEvictions);
#endif
            printPacket("fromRadioQ full, drop oldest!", old_p);''', 'Router.cpp RX overflow')
    s = sub_once(s, '''    // Nasty hack because our threading is primitive.  interfaces shouldn't need to know about routers FIXME
    setReceivedMessage();''', '''#if EMERGENCY_METRICS
    ++emergencyRxAccepted;
    if ((emergencyRxAccepted % 128U) == 1U)
        LOG_INFO("EMG_RXQ,accepted=%lu,evicted=%lu", (unsigned long)emergencyRxAccepted,
                 (unsigned long)emergencyRxEvictions);
#endif
    // Nasty hack because our threading is primitive.  interfaces shouldn't need to know about routers FIXME
    setReceivedMessage();''', 'Router.cpp RX accepted')
    return s


def reliable_impl(s: str) -> str:
    # Keep all ACK/retry behavior intact, only add low-cost aggregate counters.
    s = sub_once(s, '#include "ReliableRouter.h"', '''#include "ReliableRouter.h"
#if EMERGENCY_METRICS
static uint32_t emergencyReliableStarts = 0;
static uint32_t emergencyAckEvents = 0;
static uint32_t emergencyNakEvents = 0;
#endif''', 'ReliableRouter.cpp counters')
    s = sub_once(s, '''    if (p->want_ack) {
        DEBUG_HEAP_BEFORE;''', '''    if (p->want_ack) {
#if EMERGENCY_METRICS
        ++emergencyReliableStarts;
        if ((emergencyReliableStarts % 64U) == 1U)
            LOG_INFO("EMG_RELIABLE,starts=%lu,acks=%lu,naks=%lu", (unsigned long)emergencyReliableStarts,
                     (unsigned long)emergencyAckEvents, (unsigned long)emergencyNakEvents);
#endif
        DEBUG_HEAP_BEFORE;''', 'ReliableRouter.cpp starts')
    s = sub_once(s, '''            LOG_DEBUG("Received a %s for 0x%08x, stopping retransmissions", ackId ? "ACK" : "NAK", ackId);''', '''#if EMERGENCY_METRICS
            if (ackId) ++emergencyAckEvents;
            else ++emergencyNakEvents;
#endif
            LOG_DEBUG("Received a %s for 0x%08x, stopping retransmissions", ackId ? "ACK" : "NAK", ackId);''', 'ReliableRouter.cpp ACK/NAK')
    return s


def platformio(s: str) -> str:
    # The T-Beam environment is normally supplied by variants/*/*.ini via extra_configs, not in this file.
    if '[env:tbeam-emergency]' in s or '[env:tbeam-emergency-aging]' in s:
        raise RuntimeError('Ya existe env:tbeam-emergency, no se sobrescribe')
    return s.rstrip() + """

; EXPERIMENTAL: isolated environment, keeps existing T-Beam settings.
[env:tbeam-emergency]
extends = env:tbeam
build_flags =
  ${env:tbeam.build_flags}
  -DEMERGENCY_METRICS=1
  -DEMERGENCY_ENABLE_MODULE=1
  -DEMERGENCY_APP_PRIORITY=1
  -DEMERGENCY_QUEUE_AGING=0
  -DMESHTASTIC_EXCLUDE_MQTT=1

; Isolate the experimental aging algorithm from the reliable baseline.
[env:tbeam-emergency-aging]
extends = env:tbeam
build_flags =
  ${env:tbeam.build_flags}
  -DEMERGENCY_METRICS=1
  -DEMERGENCY_ENABLE_MODULE=1
  -DEMERGENCY_APP_PRIORITY=1
  -DEMERGENCY_QUEUE_AGING=1
  -DMESHTASTIC_EXCLUDE_MQTT=1
"""

TARGETS = {
    'src/mesh/MeshPacketQueue.h': queue_header,
    'src/mesh/MeshPacketQueue.cpp': queue_impl,
    'src/mesh/RadioLibInterface.h': radio_header,
    'src/mesh/RadioLibInterface.cpp': radio_impl,
    'src/mesh/Router.cpp': router_impl,
    'src/mesh/ReliableRouter.cpp': reliable_impl,
    'platformio.ini': platformio,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('repository', type=Path, help='Ruta al repositorio de firmware existente')
    ap.add_argument('--apply', action='store_true', help='Escribe los cambios (por defecto solo comprueba)')
    ap.add_argument('--allow-dirty', action='store_true', help='Permite cambios previos con riesgo de conflictos')
    args = ap.parse_args()
    root = args.repository.resolve()
    if not (root / '.git').exists():
        raise SystemExit(f'No es un repositorio Git: {root}')
    if not args.allow_dirty:
        status = subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], text=True).strip()
        if status:
            raise SystemExit('El árbol Git no está limpio. Guarda tus cambios o usa --allow-dirty si sabes lo que haces.')
    revision = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    changes = {}
    for name, action in TARGETS.items():
        p = root / name
        changes[p] = action(p.read_text(encoding='utf-8'))
    for src in OVERLAY.rglob('*'):
        if src.is_file():
            dest = root / src.relative_to(OVERLAY)
            if dest.exists():
                raise SystemExit(f'Se interrumpe: ya existe {dest}')
    print('Revisión local:', revision)
    print('Editados:\n' + '\n'.join(str(p.relative_to(root)) for p in changes))
    print('Añadidos:\n' + '\n'.join(str(f.relative_to(OVERLAY)) for f in OVERLAY.rglob('*') if f.is_file()))
    if not args.apply:
        print('COMPROBACIÓN correcta. Usa --apply para escribir.')
        return
    # All anchor checks complete before the first file write.
    for path, content in changes.items():
        path.write_text(content, encoding='utf-8')
    for src in OVERLAY.rglob('*'):
        if src.is_file():
            dest = root / src.relative_to(OVERLAY)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
    notes = root / 'emergency_base_sha.txt'
    notes.write_text(revision + '\n', encoding='ascii')
    print('Aplicado. SHA guardado en emergency_base_sha.txt. Ejecuta git diff --check y después pio run -e tbeam-emergency.')

if __name__ == '__main__':
    main()
