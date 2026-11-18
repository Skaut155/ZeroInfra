#pragma once
#include <stdint.h>
namespace Time { inline uint32_t getMillis() { return 1000; } inline uint32_t skipZero(uint32_t x) { return x ? x : 1; } }
