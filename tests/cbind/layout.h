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
