typedef int Id;
typedef void* Handle;
typedef short T;
namespace lib {
struct Id { long long v; };
struct Handle;
extern "C" void use_id(Id x);
extern "C" void close_h(Handle* h);
typedef Id Alias;
}
namespace a { typedef long long T; }
namespace b { using a::T; extern "C" void f(T x); typedef T BT; }
struct B { typedef long long T; };
struct D : B { typedef T DT; };
struct P : private B { typedef T PT; };
class Q { typedef long long T; public: typedef T QT; };
namespace m { typedef long long M; }
namespace k { using namespace m; extern "C" void um(M x); }
