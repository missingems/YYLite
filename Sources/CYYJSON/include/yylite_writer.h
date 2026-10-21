/*
 * yylite_writer: tiny streaming JSON writer shared by YYLite (Swift) and YYLiteObjC.
 * Writes straight into a growable malloc buffer; no intermediate tree.
 * Strings must be valid UTF-8 (Swift String / NSString UTF-8 always are); quotes, backslash
 * and control characters < 0x20 are escaped, '/' and non-ASCII are copied as is.
 */
#ifndef YYLITE_WRITER_H
#define YYLITE_WRITER_H
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct yylite_writer {
    uint8_t *buf;
    size_t len, cap;
    int32_t depth;
    bool need_comma, after_key, pretty;
    bool failed;        /* allocation failure: output is invalid */
} yylite_writer;

/* Returns false on allocation failure. */
bool yylite_w_init(yylite_writer *w, size_t capacity, bool pretty);
void yylite_w_free(yylite_writer *w);
/* Hands the buffer to the caller (free() it); the writer is reset to empty. */
uint8_t *yylite_w_take(yylite_writer *w, size_t *len);

void yylite_w_key(yylite_writer *w, const char *key, size_t len);      /* "key": */
void yylite_w_begin(yylite_writer *w, char open);                     /* '{' or '[' */
void yylite_w_end(yylite_writer *w, char close);                      /* '}' or ']' */
void yylite_w_null(yylite_writer *w);
void yylite_w_bool(yylite_writer *w, bool v);
void yylite_w_int(yylite_writer *w, int64_t v);
void yylite_w_uint(yylite_writer *w, uint64_t v);
void yylite_w_string(yylite_writer *w, const char *s, size_t len);
/* Pre-formatted number text (e.g. Swift's shortest Double.description). Not validated. */
void yylite_w_number_text(yylite_writer *w, const char *s, size_t len);
/* Shortest of %.15g/%.16g/%.17g that round-trips. Non-finite: writes null, returns false. */
bool yylite_w_double(yylite_writer *w, double v);
/* Shortest of %.6g..%.9g that round-trips as float. Non-finite: writes null, returns false. */
bool yylite_w_float(yylite_writer *w, float v);

#ifdef __cplusplus
}
#endif
#endif
