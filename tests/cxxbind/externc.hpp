#include <cstddef>
#include <cstdint>
extern "C" {
int add(int a, int b);
double scale(double x, float f);
const char* name_of(int id);
void fill(uint8_t* buf, size_t n);
void* raw(void);
unsigned long long big(long long x, unsigned short s);
int apply(int (*f)(int), int x);
bool flag(bool b);
int say(const char* fmt, ...);
int quiet(int x) noexcept;
inline int twice(int x) { return x * 2; }
}
enum Kind { KA, KB };
extern "C" Kind kind_of(int x);
namespace net {
enum class Proto : uint16_t { Tcp = 6, Udp = 17 };
extern "C" int net_port(Proto p, const char* host);
}
extern "C" int with_ref(int& r);
int not_c(int x);
