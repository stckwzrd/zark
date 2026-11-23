constexpr int Answer = 42;
constexpr unsigned Mask = 0xFFu;
constexpr long long Wide = -5000000000LL;
constexpr double Pi = 3.5;
constexpr float Half = 0.5f;
constexpr bool On = true;
static const int Limit = 100;
const char Letter = 'z';
namespace cfg {
constexpr int Depth = 3;
constexpr int Twice = Depth * 2;
namespace inner {
static const unsigned short Port = 8080;
}
}
struct Limits {
    static constexpr int Max = 7;
    static const int Min = -7;
    int v;
};
typedef int Count;
using Real = double;
typedef unsigned char Byte;
using BytePtr = Byte*;
namespace cfg {
using Id = long;
constexpr Id First = 1;
}
