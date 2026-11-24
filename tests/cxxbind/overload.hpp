namespace ui {
struct Vec2 { float x = 0; float y = 0; Vec2(float a, float b) { x = a; y = b; } };
int Combo(const char* label, int* current, const char* const* items, int count, int height);
int Combo(const char* label, int* current, const char* items, int count, int height);
bool TreeNode(const char* label);
bool TreeNode(const void* ptr_id, const char* fmt);
bool TreeNode(const char* str_id, const char* fmt);
int Slider(float* v, float lo, float hi, const char* fmt);
int Slider(double* v, double lo, double hi, const char* fmt);
int Hit(Vec2 p, Vec2 q);
float Hit(const Vec2& p, float r);
struct Buf {
    float v;
    float& at(int i);
    const float& at(int i) const;
};
}
namespace ui {
struct S {
    static int pick(int a, int b = 3);
    static int pick(double d);
    static int one(int a, int b = 4);
};
int refs(int* p);
int refs(int& r);
}
