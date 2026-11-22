#include <stddef.h>
#include <stdint.h>

typedef unsigned int u32t;
typedef signed char sc_t;
typedef unsigned char uc_t;
typedef char ch_t;
typedef short s16;
typedef unsigned short u16t;
typedef long l64;
typedef unsigned long ul64;
typedef long long ll64;
typedef unsigned long long ull64;
typedef float f32t;
typedef double f64t;
typedef _Bool b_t;
typedef size_t sz_t;
typedef int8_t i8t;
typedef uint8_t u8t;
typedef int16_t i16t;
typedef uint16_t u16x;
typedef int32_t i32t;
typedef uint32_t u32x;
typedef int64_t i64t;
typedef uint64_t u64t;
typedef ptrdiff_t diff_t;
typedef u32t again_t;
typedef int type;
typedef int (*cb_t)(void*, int);
typedef void (*vcb_t)(int);

int add(int a, int b);
int unnamed(int, char);
void nothing(void);
int say(const char* fmt, ...);
const char* name_of(unsigned char c, signed char d, _Bool ok);
size_t count(const int xs[], size_t n, int8_t a, uint16_t b, int32_t c, uint64_t d);
void call(cb_t cb, int (*direct)(int), void* ctx);
int keywords(int type, int match, int fn);
unsigned long long big(long long x, unsigned short y, short z);
int (*pick(int which))(int);
int renamed(int x) __asm__("real_renamed");
long double ld(void);
double _Complex cplx(void);
_Atomic int counter_get(void);
extern int global_x;
#define TWICE(x) ((x) * 2)
