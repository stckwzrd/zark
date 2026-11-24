struct Val { int x = 5; Val() { x = 9; } int get() const; };
struct Own { int x = 5; Own() { x = 9; } ~Own(); int get() const; };
