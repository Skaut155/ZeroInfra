#pragma once
#include "mesh/SinglePortModule.h"
struct MeshService { void sendToMesh(meshtastic_MeshPacket*) {} };
extern MeshService *service;
