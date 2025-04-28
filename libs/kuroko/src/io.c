#include <kuroko/io.h>
#include <kuroko/vm.h>

#include <stdarg.h>
#include <string.h>

#define MAX_OUTPUT_LEN 2048

int krk_fprintf(FILE* stream, const char* fmt, ...) {
    char buffer[MAX_OUTPUT_LEN];
    va_list args;
    
    va_start(args, fmt);
    
    int written = vsnprintf(buffer, MAX_OUTPUT_LEN, fmt, args);
    
    va_end(args);

    if (written < 0) {
        return -1;
    }
    
    size_t to_write = (size_t)(written > MAX_OUTPUT_LEN ? MAX_OUTPUT_LEN : written);
    
    size_t result = krk_fwrite(buffer, 1, to_write, stream);
    
    if (result < to_write) {
        return -1;
    }

    return written;
}

int krk_fputc(int c, FILE* stream) {
    size_t result = krk_fwrite(&c, sizeof(unsigned char), 1, stream);

    if (result == 1) {
        return c;
    } else {
        return EOF;
    }
}

FILE* krk_getStdout(void) {
    return stdout;
}

FILE* krk_getStderr(void) {
    return stderr;
}
