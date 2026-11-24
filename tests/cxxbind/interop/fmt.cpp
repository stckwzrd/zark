#include "fmt.hpp"
#include <cstdarg>
#include <cstdio>
#include <cstring>

FmtV::FmtV(float v) : x(v) {}

namespace fx {
static char buffer[256];
static float last_col = 0;
static char last_id[64] = "";
static void *last_ptr = nullptr;
static int ncalls = 0;

static void finish(const char *fmt, va_list ap) {
    vsnprintf(buffer, sizeof(buffer), fmt, ap);
    ncalls += 1;
}

void Text(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    finish(fmt, ap);
    va_end(ap);
}

void TextColored(const FmtV &col, const char *fmt, ...) {
    last_col = col.x;
    va_list ap;
    va_start(ap, fmt);
    finish(fmt, ap);
    va_end(ap);
}

bool TreeNode(const char *str_id, const char *fmt, ...) {
    std::snprintf(last_id, sizeof(last_id), "%s", str_id);
    va_list ap;
    va_start(ap, fmt);
    finish(fmt, ap);
    va_end(ap);
    return true;
}

bool TreeNode(const void *ptr_id, const char *fmt, ...) {
    last_ptr = const_cast<void *>(ptr_id);
    va_list ap;
    va_start(ap, fmt);
    finish(fmt, ap);
    va_end(ap);
    return true;
}

const char *last() { return buffer; }
float col() { return last_col; }
const char *str_id() { return last_id; }
int calls() { return ncalls; }
}
