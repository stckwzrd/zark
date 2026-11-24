namespace a_b { enum E : short { X = 1 }; extern "C" void g(E e); }
namespace a { namespace b { enum E : long long { Y = 2 }; } }
namespace a_b { typedef short T; }
namespace a { namespace b { typedef long long T; extern "C" void h(T e); } }
enum class Fwd : short;
enum class Fwd : short { A, B };
enum K : int;
extern "C" void usek(K k);
enum K : int { K0 };
