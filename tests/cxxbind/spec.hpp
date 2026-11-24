template<class T> struct Vec { int Size; int Capacity; T* Data; int size() const; };
typedef unsigned short Wchar;
struct Cmd { int id; };
enum Key : int { K0 };
struct IO { Vec<Wchar> chars; Vec<Cmd> cmds; Vec<Cmd*>* list; Vec<float> fl; Vec<Key> keys; Vec<int> ints; };
namespace n { struct Pair { int k; }; struct Store { Vec<Pair> data; }; }
template<class T> struct Unused { T v; };
template<class T, int N> struct Arr { T v[N]; };
struct HasArr { Arr<int, 4> a; };
int count(const Vec<Cmd>* v);
template<class T> struct Box { T v; };
template<class T> struct Box<const T*> { T* v; long extra[3]; };
struct U2 { Box<long> a; Box<long long> b; Box<char*> c; Box<const char*> d; int tail; };
template<class T> struct TA { union { T i; float f; }; int n; };
struct HT { TA<int> t; };
