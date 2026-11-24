namespace a { enum E : char { X }; typedef E TE; }
enum E : long long { G };
namespace b { using namespace ::a; typedef TE T; long long second(const T* p); }
namespace n { enum class K : char; }
enum class n::K : char { Z };
enum class K : long { Z = 5 };
long get(K k);
char getn(n::K k);
extern "C" constexpr int cx(int x) { return x + 1; }
