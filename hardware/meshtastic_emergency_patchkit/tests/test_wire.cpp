#include "../overlay/src/modules/optional/Emergency/EmergencyWire.h"
#include "../overlay/src/mesh/EmergencyQueuePolicy.h"
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
int main() {
    const uint8_t text[] = {'A','l','e','r','t','a'};
    uint8_t frame[200] = {};
    EmergencyWire::Message m = {EmergencyWire::Kind::Alert,2,1,0xaabbccdd,0,0x12345678,text,sizeof(text)};
    size_t n = EmergencyWire::serialize(frame,sizeof(frame),m);
    assert(n==EmergencyWire::HEADER_SIZE+sizeof(text));
    EmergencyWire::Message parsed = {};
    assert(EmergencyWire::parse(frame,n,parsed));
    assert(parsed.id==m.id && parsed.originNode==m.originNode && parsed.textSize==sizeof(text));
    assert(parsed.flags==1 && parsed.severity==2);
    assert(!EmergencyWire::parse(frame,19,parsed));
    frame[4]=2; assert(!EmergencyWire::parse(frame,n,parsed)); frame[4]=1;
    frame[7]=0xff; assert(!EmergencyWire::parse(frame,n,parsed)); frame[7]=1;
    assert(EmergencyQueuePolicy::effective(64,0)==64);
    assert(EmergencyQueuePolicy::effective(64,40'000)==74);
    assert(EmergencyQueuePolicy::effective(95,100'000)==99);
    assert(EmergencyQueuePolicy::effective(110,100'000)==110);
    assert(EmergencyQueuePolicy::effective(120,100'000)==120);
    EmergencyWire::Message fetch = {EmergencyWire::Kind::Fetch,0,0,0,0,0,nullptr,0};
    n = EmergencyWire::serialize(frame,sizeof(frame),fetch);
    assert(n == EmergencyWire::HEADER_SIZE);
    assert(EmergencyWire::parse(frame,n,parsed) && parsed.kind==EmergencyWire::Kind::Fetch);
    EmergencyWire::Message replay = {EmergencyWire::Kind::Replay,2,0,5,0,0x1234,text,sizeof(text)};
    n=EmergencyWire::serialize(frame,sizeof(frame),replay);
    assert(EmergencyWire::parse(frame,n,parsed) && parsed.kind==EmergencyWire::Kind::Replay);
    puts("OK: wire protocol, parser validation, FETCH/REPLAY, bounded aging");
}
