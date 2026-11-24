namespace a { enum E : char { X }; typedef E TE; }
enum E : long long { G };
namespace b { using namespace ::a; typedef TE T; long long second(const T* p); long long viat(T t); long long viate(const TE* p); }
namespace n { enum class K : char; }
enum class n::K : char { Z };
enum class K : long { Z = 5 };
long get(K k);
char getn(n::K k);
namespace u { enum V : short; }
enum u::V : short { V0 = 3, V1 };
short getv(u::V v);
namespace r { struct S; }
struct r::S { enum In { I0 }; };
extern "C" { enum Cb { CB0 = 7 }; }
int getcb(Cb c);
