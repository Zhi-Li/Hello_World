#include "Policy.h"
#include <math.h>

int sg_window_valid(SGWindow w) {
    return w.start_minute < 1440 && w.end_minute < 1440 && w.weekdays > 0 &&
        w.weekdays < 128 && w.mode < 2 && w.all_day < 2 &&
        (w.all_day || w.start_minute != w.end_minute);
}

static int contains(SGWindow w, int day, int minute) {
    if (!sg_window_valid(w)) return 0;
    if (w.all_day) return (w.weekdays & (1u << day)) != 0;
    if (w.start_minute < w.end_minute)
        return (w.weekdays & (1u << day)) && minute >= w.start_minute && minute < w.end_minute;
    int yesterday = (day + 6) % 7;
    return ((w.weekdays & (1u << day)) && minute >= w.start_minute) ||
           ((w.weekdays & (1u << yesterday)) && minute < w.end_minute);
}

int sg_recording_mode(const SGWindow *windows, size_t count, int day, int minute) {
    if (day < 0 || day > 6 || minute < 0 || minute >= 1440) return 2;
    int after_school = 0;
    for (size_t i = 0; i < count; i++) {
        if (!contains(windows[i], day, minute)) continue;
        if (windows[i].mode == 0) return 0; /* school always takes priority */
        after_school = 1;
    }
    return after_school ? 1 : 2;
}

int sg_mode(const SGWindow *windows, size_t count, int day, int minute) {
    return sg_recording_mode(windows, count, day, minute) == 1;
}

double sg_accumulate(double used, double elapsed, int after, int active, int paused, int stopped) {
    if (!isfinite(used) || used < 0) used = 0;
    /* Ignore sleep gaps, clock jumps and stalled samples, rather than billing them. */
    if (after && active && !paused && !stopped && isfinite(elapsed) && elapsed > 0 && elapsed <= 2.5)
        used += elapsed;
    return used;
}

int sg_should_block(double used, double limit, int after, int paused, int stopped) {
    return after && !paused && !stopped && isfinite(used) && isfinite(limit) && limit > 0 && used >= limit;
}
