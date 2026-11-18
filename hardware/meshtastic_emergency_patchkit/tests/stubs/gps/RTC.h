#pragma once
#include <stdint.h>
enum { RTCQualityFromNet=1 };
inline int getRTCQuality() { return 1; }
inline uint32_t getValidTime(int) { return 1500000000; }
