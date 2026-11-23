#pragma once
#include <stdint.h>
// Experimental fairness: preserves routing/control priorities >= HIGH (100).
// Low/normal priority may gain at most 25 points after prolonged waiting.
// Only used on ready packets (tx_after == 0); no mutation of original priority.
namespace EmergencyQueuePolicy {
inline uint32_t effective(uint32_t original, uint32_t waitMs)
{
    if (original >= 100) return original; // ACK/control/ALERT are never aged or overruled
    const uint32_t bonus = waitMs / 4000U > 25U ? 25U : waitMs / 4000U;
    const uint32_t raised = original + bonus;
    return raised >= 100U ? 99U : raised;
}
}
