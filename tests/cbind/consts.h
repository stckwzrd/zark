#include <limits.h>
typedef unsigned char u8_t;
enum E { A = 1, B, C = A + 4, D = -1 };
enum { ANON1 = 7, ANON2 };
typedef enum { K0, K1 = 57 } Code;
enum Wide { W1 = 0xFFFFFFFFu, W2 = W1 + 1, W3 };
enum Mixed { M1 = -1, M2 = 0x80000000 };
enum Next { N1 = 0xFFFFFFFFu, N2 };
enum Huge { H1 = 0xFFFFFFFFFFFFFFFFull };
enum Keys { KEY = ((Code)57 | (1 << 30)), KEY2 = (u8_t)0x1FF, KEY3 = (enum E)3, KEY4 = (Code)-1 > 0 };
enum {
    X1 = 1 << 31, X2 = -1 >> 1, X3 = (int)0xFFFFFFFFu, X4 = (unsigned char)300,
    X5 = (signed char)200, X6 = 7 / -2, X7 = -7 % 2, X8 = 0xFFFFFFFFu + 1,
    X9 = (0x7FFFFFFF + 1u) > 0, X10 = -1 < 0u, X11 = sizeof(long), X12 = sizeof(short) * 3,
    X13 = 1 ? 2 : 3, X14 = 0 ? 2 : -3, X15 = !5 + ~0, X16 = 077 + 0b101,
    X17 = (2 > 1) && (0 || 3), X18 = 1 == 1 != 0, X19 = 10 - 2 - 3, X20 = 1 + 2 * 3 << 1,
    X21 = (_Bool)7, X22 = -2147483647 - 1, X23 = 0x10 ^ 0x11 | 0x100 & 0x300
};
enum Chars { CH1 = 'a', CH2 = '\x1B', CH3 = '\n', CH4 = '\0', CH5 = '\'', CH6 = '\177', CH7 = '\\', CH8 = '"', CH9 = '\b' };
struct pair { int a; int b; };
enum Bad1 { BV1 = 1, BV2 = sizeof(struct pair) };
int uses_bad(enum Bad1 b);
enum { BV3 = (int)2.5 };
enum __attribute__((aligned(8))) Al { AL1 = 1 };
enum Clash { CL1 = -1, CL2 = 0xFFFFFFFFFFFFFFFFull };
enum Small : short { S1 = -2, S2 };
enum Wide wide_of(enum Small s, Code c);

#define N 42
enum { FROM_MACRO = N * 2 };
#define MASK (1u << 3)
#define NAME "text"
#define F 1.5
#define SUM (N + MASK)
#define CH 'a'
#define OBJ_ALIAS N
#define STR_ALIAS NAME
#define HEX 0x10
#define OR (A | B)
#define NEG -5
#define NEGF -1.5
#define BIGU 0xFFFFFFFFu
#define WRAP (0xFFFFFFFFu + 1)
#define SHL40 (1UL << 40)
#define ALLONES (~0ULL)
#define LONGMAX 0x7FFFFFFFFFFFFFFF
#define TEXTP "a{b}\n" "c"
#define LATE (EARLY * 2)
#define EARLY 3
#define EXPR 1 + 2
#define USE_EXPR (EXPR * 3)
#define USE_ENUM (C + 1)
#define CAST ((u8_t)0x1FF)
#define SZ sizeof(int)
#define ESC '\x1B'
#define FROMSYS INT_MAX
#define SAME 5
#undef SAME
#define SAME 5
#define GONE 1
#undef GONE
#define CHANGED 5
#define CHANGED 6
#define USES_CHANGED (CHANGED + 1)
#define TWICE(x) ((x) * 2)
#define EMPTY
#define CALL TWICE(2)
#define SELF SELF
#define DIV0 (1 / 0)
#define SHNEG (1 << -1)
#define SHBIG (1 << 32)
#define OVF (2147483647 + 1)
#define FLT 2.5f
#define UNKNOWN (foo + 1)
#define LSTR L"wide"
#define REDO 1
#undef REDO
#define REDO 2
