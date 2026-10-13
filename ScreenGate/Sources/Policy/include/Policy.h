#ifndef SCREENGATE_POLICY_H
#define SCREENGATE_POLICY_H
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint16_t start_minute;
    uint16_t end_minute;
    uint8_t weekdays; /* bit 0 Sunday ... bit 6 Saturday; start day for overnight */
    uint8_t mode;     /* 0 in-school, 1 after-school */
    uint8_t all_day;
} SGWindow;

int sg_window_valid(SGWindow window);
int sg_mode(const SGWindow *windows, size_t count, int weekday, int minute);
double sg_accumulate(double used, double elapsed, int after_school, int active, int paused, int stopped);
int sg_should_block(double used, double limit, int after_school, int paused, int stopped);
#endif
