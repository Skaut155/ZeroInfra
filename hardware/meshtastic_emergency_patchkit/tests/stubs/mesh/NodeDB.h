#pragma once
#include <stdint.h>
struct NodeDB { uint32_t getNodeNum() const { return 0x12345678; } };
extern NodeDB *nodeDB;
