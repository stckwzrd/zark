#include "init.hpp"

Val::Val() { x = 9; }
int Val::get() const { return x; }

Own::Own() { x = 9; }
Own::~Own() {}
int Own::get() const { return x; }

int cpp_val() { return Val().x; }
int cpp_own() { return Own().x; }
