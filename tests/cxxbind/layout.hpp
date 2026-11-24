namespace geo {
struct Vec { double x, y; int k; };
class Priv { double d; };
struct Mixed { int a; private: int b; public: char c; protected: short d; public: double e; };
struct NP { NP(); int n; char c; };
struct Tail : NP { char t; };
struct Shape { virtual ~Shape(); int id; };
struct Circle : Shape { double r; };
struct alignas(16) A16 { char c; };
struct AF { char c; alignas(8) int x; };
struct M1 { int a; };
struct M2 { virtual void f(); int b; };
struct MM : M1, M2 { int c; };
struct PrivBase : private Vec { int p; };
struct VB { int v; };
struct VD : virtual VB { int w; };
struct E {};
struct DE : E { int x; };
struct Hide : Vec { int x; };
struct Ref { int& r; int v; };
struct Arr { Vec vs[2]; int n[3]; Vec* next; };
#pragma pack(push, 1)
struct Pk { char c; int x; };
#pragma pack(pop)
struct UsePk { Pk p; char tail; };
struct NU { [[no_unique_address]] E e; int k; };
}
