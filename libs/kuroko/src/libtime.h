#pragma once
/**
 * @file libtime.h
 * @brief Time-related functions for Windows without MinGW.
 */

#if defined(_WIN32) && defined (__clang__)

#include <time.h>

#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC 1

extern struct tm *localtime_r(const time_t *timep, struct tm *result);

extern struct tm *gmtime_r(const time_t *timep, struct tm *result);

#endif
