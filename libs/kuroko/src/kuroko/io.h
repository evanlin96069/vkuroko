#pragma once
/**
 * @file io.h
 * @brief Custom IO functions.
 */
 #include <stdio.h>
 #include "kuroko.h"

// User-defined functions

extern KRK_PUBLIC size_t krk_fwrite(void const* buffer, size_t elementSize, size_t elementCount, FILE* stream); 

extern KRK_PUBLIC int krk_fflush(FILE* stream);

// Some languages might not has a good way of getting stdout or stderr

extern KRK_PUBLIC FILE* krk_getStdout(void);

extern KRK_PUBLIC FILE* krk_getStderr(void);

// IO functions implemented using krk_fwrite

extern KRK_PUBLIC int krk_fprintf(FILE* stream, const char* fmt, ...);

extern KRK_PUBLIC int krk_fputc(int c, FILE* stream);
