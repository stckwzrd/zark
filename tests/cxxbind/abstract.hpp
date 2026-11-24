struct A { virtual ~A(); virtual void f() = 0; };
struct B { virtual void g() = 0; B(int); ~B(); };
