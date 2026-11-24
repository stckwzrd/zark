namespace c {
int f(int a, int b = 0);
int f_1(int a);
struct S {
    int v;
    int match(int x);
};
}
namespace c {
struct Own { int v; Own(int k); ~Own(); void assign(Own* o); void assign_move(Own* o); };
struct Own_own { int z; };
}
