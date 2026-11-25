#pragma once
template<class T> struct Wrap { T v; };
struct UsesWrap { Wrap<int[3]> w; };
template struct Wrap<int[3]>;
