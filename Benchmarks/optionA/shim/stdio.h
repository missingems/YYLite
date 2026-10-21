#pragma once
#include <stddef.h>
#include <stdarg.h>
typedef struct __sFILE FILE;
FILE *fopen(const char *, const char *);
int fclose(FILE *);
size_t fread(void *, size_t, size_t, FILE *);
size_t fwrite(const void *, size_t, size_t, FILE *);
int fseek(FILE *, long, int); long ftell(FILE *); int ferror(FILE *);
int sprintf(char *, const char *, ...);
int snprintf(char *, size_t, const char *, ...);
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define EOF (-1)
int snprintf(char *, size_t, const char *, ...);
