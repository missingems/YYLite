#include "yylite_writer.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

/* ---- Hot paths: built for speed, not minsize (they are a few hundred bytes). ---- */

static bool grow(yylite_writer *w, size_t need) {
    if (w->failed) return false;
    size_t cap = w->cap ? w->cap : 64;
    while (cap < need) cap *= 2;
    uint8_t *nb = (uint8_t *)realloc(w->buf, cap);
    if (!nb) { w->failed = true; return false; }
    w->buf = nb; w->cap = cap;
    return true;
}
/* Ensures room for n more bytes. */
#define RESERVE(w, n) ((w)->len + (n) <= (w)->cap || grow((w), (w)->len + (n)))

static inline void put(yylite_writer *w, const void *p, size_t n) {
    if (!RESERVE(w, n)) return;
    memcpy(w->buf + w->len, p, n);
    w->len += n;
}

/* Non-zero if any byte of x is < 0x20, '"' or '\\' (exact when zero; may over-report otherwise). */
static inline uint64_t needs_escape8(uint64_t x) {
    const uint64_t one = 0x0101010101010101ULL, high = 0x8080808080808080ULL;
    uint64_t q = x ^ (one * 0x22), b = x ^ (one * 0x5C);
    return (((x - one * 0x20) & ~x) | ((q - one) & ~q) | ((b - one) & ~b)) & high;
}

/* Quoted, escaped string. Plain 8-byte blocks are copied in one go; a block that has something
 * to escape is done byte by byte. Room for the plain case is reserved up front; each escape
 * re-checks room for itself plus the rest. */
static void escape(yylite_writer *w, const char *s, size_t n) {
    static const char hex[] = "0123456789abcdef";
    const uint8_t *p = (const uint8_t *)s;
    if (!RESERVE(w, n + 2)) return;
    uint8_t *o = w->buf + w->len;
    *o++ = '"';
    size_t i = 0;
    while (i < n) {
        if (i + 8 <= n) {
            uint64_t x; memcpy(&x, p + i, 8);
            if (!needs_escape8(x)) { memcpy(o, &x, 8); o += 8; i += 8; continue; }
        }
        size_t end = i + 8 < n ? i + 8 : n;
        for (; i < end; i++) {
            uint8_t c = p[i];
            if (c >= 0x20 && c != '"' && c != '\\') { *o++ = c; continue; }
            w->len = (size_t)(o - w->buf);
            if (!RESERVE(w, (n - i) + 6 + 1)) return;   /* escape + remaining + closing quote */
            o = w->buf + w->len;
            *o++ = '\\';
            switch (c) {
                case '"': *o++ = '"'; break;
                case '\\': *o++ = '\\'; break;
                case '\n': *o++ = 'n'; break;
                case '\r': *o++ = 'r'; break;
                case '\t': *o++ = 't'; break;
                case '\b': *o++ = 'b'; break;
                case '\f': *o++ = 'f'; break;
                default: *o++ = 'u'; *o++ = '0'; *o++ = '0'; *o++ = (uint8_t)hex[c >> 4]; *o++ = (uint8_t)hex[c & 15]; break;
            }
        }
    }
    *o++ = '"';
    w->len = (size_t)(o - w->buf);
}

#if defined(__clang__)
#pragma clang attribute push (__attribute__((minsize)), apply_to = function)
#endif

bool yylite_w_init(yylite_writer *w, size_t capacity, bool pretty) {
    memset(w, 0, sizeof(*w));
    w->pretty = pretty;
    return grow(w, capacity < 64 ? 64 : capacity);
}
void yylite_w_free(yylite_writer *w) { free(w->buf); memset(w, 0, sizeof(*w)); }
uint8_t *yylite_w_take(yylite_writer *w, size_t *len) {
    uint8_t *b = w->buf;
    *len = w->len;
    w->buf = NULL; w->len = w->cap = 0;
    return b;
}

static void newline(yylite_writer *w) {
    size_t n = 1 + (size_t)w->depth * 2;
    if (!RESERVE(w, n)) return;
    w->buf[w->len] = '\n';
    memset(w->buf + w->len + 1, ' ', n - 1);
    w->len += n;
}
/* Comma / indentation before a value; nothing right after a key. */
static void value_start(yylite_writer *w) {
    if (w->after_key) { w->after_key = false; return; }
    if (w->need_comma) put(w, ",", 1);
    if (w->pretty && w->depth > 0) newline(w);
}

void yylite_w_key(yylite_writer *w, const char *key, size_t len) {
    if (w->need_comma) put(w, ",", 1);
    if (w->pretty) newline(w);
    escape(w, key, len);
    if (w->pretty) put(w, ": ", 2); else put(w, ":", 1);
    w->need_comma = false;
    w->after_key = true;
}
void yylite_w_begin(yylite_writer *w, char open) {
    value_start(w);
    put(w, &open, 1);
    w->depth++;
    w->need_comma = false;
}
void yylite_w_end(yylite_writer *w, char close) {
    w->depth--;
    if (w->pretty && w->need_comma) newline(w);
    put(w, &close, 1);
    w->need_comma = true;
}
void yylite_w_null(yylite_writer *w) { value_start(w); put(w, "null", 4); w->need_comma = true; }
void yylite_w_bool(yylite_writer *w, bool v) {
    value_start(w);
    if (v) put(w, "true", 4); else put(w, "false", 5);
    w->need_comma = true;
}
static void write_u64(yylite_writer *w, uint64_t m, bool neg) {
    char t[21]; int n = 0;
    do { t[20 - n++] = (char)('0' + m % 10); m /= 10; } while (m);
    if (neg) t[20 - n++] = '-';
    put(w, t + 21 - n, (size_t)n);
}
void yylite_w_int(yylite_writer *w, int64_t v) {
    value_start(w);
    write_u64(w, v < 0 ? (uint64_t)0 - (uint64_t)v : (uint64_t)v, v < 0);
    w->need_comma = true;
}
void yylite_w_uint(yylite_writer *w, uint64_t v) { value_start(w); write_u64(w, v, false); w->need_comma = true; }
void yylite_w_string(yylite_writer *w, const char *s, size_t len) {
    value_start(w); escape(w, s, len); w->need_comma = true;
}
void yylite_w_number_text(yylite_writer *w, const char *s, size_t len) {
    value_start(w); put(w, s, len); w->need_comma = true;
}

/* snprintf may use ',' as decimal separator in some locales; JSON needs '.'. */
/* Keeps the value a real number: "100" -> "100.0", "-0" -> "-0.0" (so -0.0 survives a re-parse). */
static void put_num(yylite_writer *w, char *b, int n) {
    bool real = false;
    for (int i = 0; i < n; i++) {
        if (b[i] == ',') b[i] = '.';
        if (b[i] == '.' || b[i] == 'e') real = true;
    }
    if (!real && n < 30) { b[n++] = '.'; b[n++] = '0'; }
    yylite_w_number_text(w, b, (size_t)n);
}
bool yylite_w_double(yylite_writer *w, double v) {
    if (!isfinite(v)) { yylite_w_null(w); return false; }
    char b[32]; int n = 0;
    for (int prec = 15; prec <= 17; prec++) {
        n = snprintf(b, sizeof b, "%.*g", prec, v);
        if (prec == 17 || strtod(b, NULL) == v) break;   /* strtod reads '.' in the C locale */
    }
    put_num(w, b, n);
    return true;
}
bool yylite_w_float(yylite_writer *w, float v) {
    if (!isfinite(v)) { yylite_w_null(w); return false; }
    char b[32]; int n = 0;
    for (int prec = 6; prec <= 9; prec++) {
        n = snprintf(b, sizeof b, "%.*g", prec, (double)v);
        if (prec == 9 || strtof(b, NULL) == v) break;
    }
    put_num(w, b, n);
    return true;
}

#if defined(__clang__)
#pragma clang attribute pop
#endif
