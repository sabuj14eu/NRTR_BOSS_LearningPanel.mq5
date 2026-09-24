// Minimal MQL5 language shim: types and pure functions used by the engine.
#pragma once
#include <algorithm>
#include <cctype>
#include <cfloat>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

typedef std::string string;
typedef long long datetime;
typedef unsigned int color;
typedef unsigned long ulong;   // 64-bit on LP64 (matches glibc)
typedef unsigned short ushort;
typedef unsigned char uchar;
typedef unsigned int uint;

#define EMPTY_VALUE DBL_MAX

template <class T> int ArrayResize(std::vector<T> &a, int n, int reserve = 0)
{
   (void)reserve;
   if(n < 0) n = 0;
   a.resize((size_t)n);
   return n;
}
template <class T> int ArraySize(const std::vector<T> &a) { return (int)a.size(); }
template <class T, class V> void ArrayInitialize(std::vector<T> &a, V v) { for(auto &x : a) x = (T)v; }

template <class A, class B> auto MathMax(A a, B b) -> decltype(a + b) { return a > b ? a : b; }
template <class A, class B> auto MathMin(A a, B b) -> decltype(a + b) { return a < b ? a : b; }
template <class T> T MathAbs(T v) { return v < 0 ? -v : v; }
inline double MathFloor(double v) { return std::floor(v); }
inline double MathCeil(double v) { return std::ceil(v); }
inline double MathRound(double v) { return std::round(v); }
inline double MathPow(double a, double b) { return std::pow(a, b); }
inline double NormalizeDouble(double v, int d)
{
   double p = std::pow(10.0, d);
   return std::round(v * p) / p;
}

inline string DoubleToString(double v, int d = 8)
{
   char b[128];
   std::snprintf(b, sizeof b, "%.*f", d, v);
   return b;
}
inline string IntegerToString(long long v, int len = 0, ushort fill = ' ')
{
   std::string s = std::to_string(v);
   while((int)s.size() < len) s.insert(s.begin(), (char)fill);
   return s;
}
inline bool StringToUpper(string &s)
{
   for(auto &c : s) c = (char)std::toupper((unsigned char)c);
   return true;
}
inline int StringLen(const string &s) { return (int)s.size(); }
inline int StringFind(const string &s, const string &sub, int start = 0)
{
   size_t p = s.find(sub, (size_t)start);
   return p == std::string::npos ? -1 : (int)p;
}
inline string StringSubstr(const string &s, int start, int len = -1)
{
   if(start < 0 || start >= (int)s.size()) return "";
   return len < 0 ? s.substr((size_t)start) : s.substr((size_t)start, (size_t)len);
}
inline ushort StringGetCharacter(const string &s, int pos)
{
   return (pos >= 0 && pos < (int)s.size()) ? (ushort)(unsigned char)s[(size_t)pos] : 0;
}
// MQL strings are UTF-16; here a code point becomes UTF-8
inline string ShortToString(ushort cp)
{
   std::string o;
   if(cp < 0x80) o += (char)cp;
   else if(cp < 0x800) { o += (char)(0xC0 | (cp >> 6)); o += (char)(0x80 | (cp & 0x3F)); }
   else { o += (char)(0xE0 | (cp >> 12)); o += (char)(0x80 | ((cp >> 6) & 0x3F)); o += (char)(0x80 | (cp & 0x3F)); }
   return o;
}
