struct FmtVec { float x; FmtVec(float v); };

namespace fx {
void Text(const char* fmt, ...) __attribute__((format(printf, 1, 2)));
void TextColored(const FmtVec& col, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
bool TreeNode(const char* str_id, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
bool TreeNode(const void* ptr_id, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
void Plain(const char* fmt, ...);
void TextV(const char* fmt, __builtin_va_list args);
void Scan(const char* fmt, ...) __attribute__((format(scanf, 1, 2)));
}
