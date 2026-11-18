#pragma once
#include "mesh/SinglePortModule.h"
struct FakePool { void release(meshtastic_MeshPacket*) {} };
extern FakePool packetPool;
