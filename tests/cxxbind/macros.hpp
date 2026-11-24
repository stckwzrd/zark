#include <cstdio>
#include <string>

#define MAC_VERSION "1.2"
#define MAC_NUM 42
#define MAC_RATIO 1.5
#define MAC_NEG -7
#define MAC_EXPR (3 + 4)
#define MAC_BASE 3
#define MAC_DERIVED (MAC_BASE * 2)
#define MAC_TWO "a" "b"
#define MAC_SIZE sizeof(int)
#define MAC_UNKNOWN (NOPE + 1)
#define MAC_FN(x) ((x) + 1)
#define MAC_EMPTY

struct MacroClash { int v; };
#define MacroClash 7
