#pragma once
template<class T> struct Box { T v; };
struct UsesBox { Box<int> b; };
template struct Box<int>;
