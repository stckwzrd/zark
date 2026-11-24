struct Val { int x = 5; Val(); int get() const; };
struct Own { int x = 5; Own(); ~Own(); int get() const; };
int cpp_val();
int cpp_own();
