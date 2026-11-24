namespace cfg {
enum class Mode : unsigned char { A, B };
struct Vec2 { float x; float y; Vec2(float a, float b) { x = a; y = b; } };
int literal(int a, int b = 4);
int expr(int a, int b = 2 + 3 * 4);
int en(Mode m = Mode::B);
int cls(Vec2 v = Vec2(1.0, 2.0));
int both(int a, int b = 2);
int both(int a, int b, int c);
int both(const char* s);
}
