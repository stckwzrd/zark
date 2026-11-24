struct Tmp { long a; long b; };
Tmp mk();
inline int f() { struct Tmp { char c; }; Tmp t; return sizeof(t); }
namespace ns {
inline int g() { struct Item { char c; }; Item i; return sizeof(i); }
struct Item { long a; long b; long c; };
Item mkitem();
}
struct Item { int q; };
Item mkq();
struct Fine { int a; };
Fine fine();
