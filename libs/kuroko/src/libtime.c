#include "libtime.h"

#if defined(_WIN32) && defined (__clang__)

#include <windows.h>

static struct tm tm;

struct tm *localtime_r(const time_t *timep, struct tm *result) {
    if (localtime_s(&tm, timep) == 0) {
        *result = tm;
        return &tm;
    }
    return NULL;
}

struct tm *gmtime_r(const time_t *timep, struct tm *result) {
if (gmtime_s(&tm, timep) == 0) {
        *result = tm;
        return &tm;
    }
    return NULL;
}

#endif