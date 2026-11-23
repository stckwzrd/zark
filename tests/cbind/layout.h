typedef int aint __attribute__((aligned(16)));
struct al { char c; aint x; };
typedef float v4 __attribute__((vector_size(16)));
v4 vadd(v4 a, v4 b);
typedef int di __attribute__((mode(DI)));
di dmode(void);
struct fv { int n; float v __attribute__((vector_size(16))); };
struct fm { int m __attribute__((mode(DI))); };
#pragma pack(push, 1)
struct pk { char c; int x; };
#pragma pack(pop)
struct unpk { char c; int x; };
#pragma pack(2)
struct pk2 { char c; int x; };
#pragma pack()
struct unpk2 { char c; int x; };
enum E8 : unsigned char { A8 = 1 };
struct e8s { enum E8 e; char c; };
enum __attribute__((packed)) EP { AP = 1 };
struct eps { enum EP e; char c; };
typedef enum { PX = 1 } __attribute__((packed)) pe_t;
enum Big { BIG = 0x100000000 };
enum Neg { UB = 0xffffffffu };
enum Ok { OA, OB = 5, OC = OB << 2, OD = 'a', OE = -1, OF = BIG >> 8 };
struct es { enum Big b; enum Ok o; };
int uses_neg(enum Neg n);
int uses_ok(enum Ok o);
int uses_e8(enum E8 e);
struct bits { unsigned a : 3; unsigned b : 5; char c; int d; long e; };
struct pkd { char c; int x; short s; } __attribute__((packed));
struct ald { char c; } __attribute__((aligned(8)));
struct alf { char c; _Alignas(8) int x; };
struct al16 { char c; } __attribute__((aligned(16)));
struct usesbits { struct bits b[2]; struct pkd p; struct alf f; };
struct bitu { union { int i; unsigned flag : 1; } u; short tail : 4; };
int takebits(struct bits b);
int takebitsp(struct bits* b);
int takepkd(struct pkd p);
int takeald(struct ald a);
#pragma pack(2)
union a3 { char c; int i; double d; char arr[9]; };
#pragma pack()
int takefv(struct fv v);
struct fv2 { v4 a; };
float takefv2(struct fv2 v);
struct fv3 { struct fv2 in; };
struct fv3 mkfv3(void);
struct cxs { _Complex double z; };
double takecx(struct cxs c);
struct hs { _Float16 a, b; };
int takehs(struct hs h);
struct lds { long double a, b; };
int takelds(struct lds l);
typedef float f4a __attribute__((aligned(4)));
struct fa2 { f4a x, y; };
float takefa2(struct fa2 f);
