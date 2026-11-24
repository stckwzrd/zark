#include "boxes.hpp"

BI mk_i() { return BI{1}; }
BCI mk_ci() { return BCI{2}; }
BVI mk_vi() { return BVI{3}; }
BCVI mk_cvi() { return BCVI{4}; }
BX mk_x() { return BX{ci32{5, 6}}; }
BF mk_f() { return BF{Foo{7, 'a'}}; }
BCF mk_cf() { return BCF{Foo{8, 'b'}}; }
BCFOO mk_cfoo() { return BCFOO{cFoo{{9, 10, 11}}}; }
BP mk_p(int* p) { return BP{p}; }
BPC mk_pc(const int* p) { return BPC{p}; }
BCP mk_cp(int* p) { return BCP{p}; }
BBC mk_bbc() { return BBC{BCI{12}}; }
BBX mk_bbx() { return BBX{BX{ci32{13, 14}}}; }
BBI mk_bbi() { return BBI{BI{15}}; }
BE mk_e() { return BE{E1}; }
BCE mk_ce() { return BCE{E0}; }
BMY mk_my() { return BMY{16}; }
BCINT mk_cint() { return BCINT{17}; }
BIP mk_ip(int* p) { return BIP{p}; }
BCFT mk_cft() { return BCFT{Foo{18, 'c'}}; }
int sum_ci(Box<const int> b) { return b.v + 100; }
long sum_x(Box<ci32> b) { return b.v.q + b.v.r + 100; }
