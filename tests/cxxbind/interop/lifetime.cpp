#include "lifetime.hpp"
namespace life {
static int nctors = 0;
static int ndtors = 0;
static int live = 0;
Counter::Counter(int k) : id(k) { nctors += 1; live += 1; }
Counter::Counter(const Counter& o) : id(o.id) { nctors += 1; live += 1; }
Counter::~Counter() { ndtors += 1; live -= 1; }
int Counter::value() const { return id; }
void Counter::set(int v) { id = v; }
Counter Counter::bump(int k) const { return Counter(id + k); }
Counter Counter::make(int k) { return Counter(k); }
int Counter::alive() { return live; }
void drop(Counter c) { (void)c; }
Counter make_one(int k) { return Counter(k); }
int ctors() { return nctors; }
int dtors() { return ndtors; }
}
