#include "alias.hpp"

int use_alias(const Alias &a, Alias *p) {
    p->v += 1;
    return a.v;
}
