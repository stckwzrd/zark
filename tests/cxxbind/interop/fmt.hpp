struct FmtV { float x; FmtV(float v); };

namespace fx {
void Text(const char* fmt, ...) __attribute__((format(printf, 1, 2)));
void TextColored(const FmtV& col, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
bool TreeNode(const char* str_id, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
bool TreeNode(const void* ptr_id, const char* fmt, ...) __attribute__((format(printf, 2, 3)));
const char* last();
float col();
const char* str_id();
int calls();
}
