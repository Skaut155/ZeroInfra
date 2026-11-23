#include "EmergencyGpsText.h"
#include <cassert>
#include <cstdint>
#include <cstring>
#include <string>

using EmergencyGpsText::Position;

bool accept(const char *text, int32_t lat, int32_t lon, const char *body)
{
    Position p{};
    if (!EmergencyGpsText::parse(reinterpret_cast<const uint8_t *>(text), strlen(text), p)) return false;
    return p.latitudeE5 == lat && p.longitudeE5 == lon && std::string(text + p.bodyOffset) == body;
}

bool reject(const char *text)
{
    Position p{};
    return !EmergencyGpsText::parse(reinterpret_cast<const uint8_t *>(text), strlen(text), p);
}

int main()
{
    assert(accept("@41.38879,2.11296 SOS", 4138879, 211296, "SOS"));
    assert(accept("@-89.99999,-179.99999 Necesito ayuda", -8999999, -17999999, "Necesito ayuda"));
    assert(accept("@90.00000,180.00000 SOS", 9000000, 18000000, "SOS"));
    assert(accept("@0.00000,-0.00001 Prueba", 0, -1, "Prueba"));
    assert(reject("SOS"));
    assert(reject("@91.00000,2.00000 SOS"));
    assert(reject("@41.00000,181.00000 SOS"));
    assert(reject("@41.388790,2.11296 SOS"));
    assert(reject("@41.38879,2.112960 SOS"));
    assert(reject("@41.38879;2.11296 SOS"));
    assert(reject("@41.38879,2.11296"));
    assert(reject("@-,2.00000 SOS"));
    assert(reject("@41.3887,2.11296 SOS"));
    assert(reject("@9999.00000,2.00000 SOS"));
    assert(reject("@41.38879,2.11296 "));
    assert(reject("@+41.38879,2.11296 SOS"));
    return 0;
}
