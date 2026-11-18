#pragma once
#include <stdint.h>
#include <stddef.h>
// EDIT THIS LIST: the full 32-bit node numbers allowed to originate emergency alerts.
// {0} means nobody is authorized: this fail-closed default is intentional.
// A whitelist protects against accidents, but does NOT replace cryptographic identity verification.
static constexpr uint32_t EMERGENCY_AUTHORIZED_ORIGINS[] = {0};
static constexpr uint32_t EMERGENCY_CACHE_MS = 60UL * 60UL * 1000UL; // dedup lifetime since reception
static constexpr size_t EMERGENCY_HISTORY_SLOTS = 16; // RAM-only bounded alert history
static constexpr size_t EMERGENCY_STORED_ALERTS = 8; // ~1.5 KiB bounded RAM for alert fetch
static constexpr uint32_t EMERGENCY_FETCH_COOLDOWN_MS = 5000;
static constexpr uint32_t EMERGENCY_RECEIPT_COOLDOWN_MS = 2000;
#ifndef EMERGENCY_ENABLE_RECEIPTS
#define EMERGENCY_ENABLE_RECEIPTS 1
#endif
