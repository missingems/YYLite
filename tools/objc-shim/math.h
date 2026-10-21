#pragma once
#define HUGE_VAL __builtin_huge_val()
#define INFINITY __builtin_inff()
#define NAN __builtin_nanf("")
#define isnan(x) __builtin_isnan(x)
#define signbit(x) __builtin_signbit(x)
#define isfinite(x) __builtin_isfinite(x)
