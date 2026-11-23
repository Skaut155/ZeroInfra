#pragma once
// Parse the optional ZeroInfra EMG1 v1 text prefix: "@lat,lon message".
// Example: @41.38879,2.11296 SOS
// No dynamic allocation, no floating-point conversion, and no change to EMG1 framing.
#include <stddef.h>
#include <stdint.h>

namespace EmergencyGpsText {

struct Position {
    int32_t latitudeE5 = 0;   // decimal degrees * 100000
    int32_t longitudeE5 = 0;  // decimal degrees * 100000
    size_t bodyOffset = 0;    // index of text after separating space
};

// Parse one signed, fixed-five-decimal coordinate. Maximum 3 integer digits.
inline bool readCoordinate(const uint8_t *bytes, size_t size, size_t &offset,
                           int32_t maxAbsE5, int32_t &coordinate)
{
    if (!bytes || offset >= size) return false;
    bool negative = false;
    if (bytes[offset] == '-') {
        negative = true;
        ++offset;
    }
    uint32_t whole = 0;
    size_t digits = 0;
    while (offset < size && bytes[offset] >= '0' && bytes[offset] <= '9') {
        if (++digits > 3) return false;
        whole = whole * 10U + uint32_t(bytes[offset++] - '0');
    }
    if (!digits || offset >= size || bytes[offset++] != '.') return false;

    uint32_t fraction = 0;
    for (unsigned i = 0; i < 5; ++i) {
        if (offset >= size || bytes[offset] < '0' || bytes[offset] > '9') return false;
        fraction = fraction * 10U + uint32_t(bytes[offset++] - '0');
    }
    // Exact precision: a sixth decimal digit is not accepted.
    if (offset < size && bytes[offset] >= '0' && bytes[offset] <= '9') return false;
    const uint32_t absolute = whole * 100000U + fraction;
    if (absolute > uint32_t(maxAbsE5)) return false;
    coordinate = negative ? -int32_t(absolute) : int32_t(absolute);
    return true;
}

// Returns false for SOS without a position, invalid coordinates, or malformed input.
// Does not treat a missing position as an invalid emergency.
inline bool parse(const uint8_t *text, size_t size, Position &result)
{
    if (!text || size < 5 || text[0] != '@') return false;
    size_t i = 1;
    Position found = {};
    if (!readCoordinate(text, size, i, 9000000, found.latitudeE5)) return false;
    if (i >= size || text[i++] != ',') return false;
    if (!readCoordinate(text, size, i, 18000000, found.longitudeE5)) return false;
    // Flutter puts one space between the GPS prefix and the SOS text.
    if (i >= size || text[i] != ' ') return false;
    while (i < size && text[i] == ' ') ++i;
    if (i == size) return false; // keep at least one SOS body byte
    found.bodyOffset = i;
    result = found;
    return true;
}

} // namespace EmergencyGpsText
