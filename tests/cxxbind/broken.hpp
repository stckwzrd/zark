typedef int Id;
namespace other {
typedef long Id;
}
namespace n {
using other::Id;
void take(Id x);
int fine(int x);
}
consteval int sq(int x) { return x * x; }
int old(int x) __attribute__((unavailable("gone")));
