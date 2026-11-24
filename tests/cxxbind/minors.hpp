struct B1 { int bf : 3; int plain; };
struct B2 : B1 { int more; };
struct Flex { int n; char data[]; };
template<class T> struct Box { T v; };
struct UB { Box<bool> b; Box<int> i; int z; };
namespace x { namespace { struct An { int a; }; } }
