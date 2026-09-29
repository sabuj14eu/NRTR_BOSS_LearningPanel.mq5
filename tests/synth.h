// Deterministic synthetic metal prices: trending regimes + noise, on the
// symbol's tick grid. 15M bars are aggregated from the 5M bars so the two
// timeframes are consistent exactly as they are in MT5.
#pragma once
#include <cstdint>
#include <random>
#include <vector>

struct SBar
{
   long long t;
   double o, h, l, c;
};

struct Synth
{
   std::mt19937_64 rng;
   explicit Synth(uint64_t seed) : rng(seed) {}
   double uni() { return (double)(rng() >> 11) * (1.0 / 9007199254740992.0); }
   double gauss()   // Box-Muller: portable, unlike std::normal_distribution
   {
      double u1 = uni(), u2 = uni();
      if(u1 < 1e-300) u1 = 1e-300;
      return std::sqrt(-2.0 * std::log(u1)) * std::cos(6.283185307179586 * u2);
   }
};

inline double snap(double p, double tick) { return std::round(p / tick) * tick; }

// generic bar generator: `sec` seconds per bar, regimes of regMin..regMax bars
inline std::vector<SBar> genBars(uint64_t seed, int n, long long start, double price, double tick, double vol,
                                 int sec, int regMin, int regMax)
{
   Synth s(seed);
   std::vector<SBar> v;
   v.reserve((size_t)n);
   double drift = 0.0;
   int left = 0;
   double c = snap(price, tick);
   for(int i = 0; i < n; i++)
   {
      if(left <= 0)
      {
         left = regMin + (int)(s.uni() * (regMax - regMin));
         double r = s.uni();
         drift = (r < 0.4) ? vol * 0.35 : (r < 0.8 ? -vol * 0.35 : 0.0);
      }
      left--;
      double o = c;
      double nc = snap(o + drift + vol * s.gauss(), tick);
      double h = snap(std::max(o, nc) + std::fabs(vol * 0.6 * s.gauss()), tick);
      double l = snap(std::min(o, nc) - std::fabs(vol * 0.6 * s.gauss()), tick);
      v.push_back({start + (long long)i * sec, o, h, l, nc});
      c = nc;
   }
   return v;
}

// the original 5M generator (unchanged sequence for the indicator tests)
inline std::vector<SBar> gen5m(uint64_t seed, int n, long long start, double price, double tick, double vol)
{
   return genBars(seed, n, start, price, tick, vol, 300, 120, 420);
}
// 1M bars with regimes long enough to build M5 structure
inline std::vector<SBar> gen1m(uint64_t seed, int n, long long start, double price, double tick, double vol)
{
   return genBars(seed, n, start, price, tick, vol, 60, 600, 2100);
}

inline std::vector<SBar> agg(const std::vector<SBar> &m5, int sec)
{
   std::vector<SBar> out;
   for(const SBar &b : m5)
   {
      long long t = (b.t / sec) * sec;
      if(out.empty() || out.back().t != t)
         out.push_back({t, b.o, b.h, b.l, b.c});
      else
      {
         SBar &a = out.back();
         a.h = std::max(a.h, b.h);
         a.l = std::min(a.l, b.l);
         a.c = b.c;
      }
   }
   return out;
}
