#include "Policy.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>

int main(void) {
    SGWindow defaults[] = {
        {540, 930, 0x3e, 0, 0}, /* weekday school 09:00–15:30 */
        {0, 0, 0x7f, 1, 1}     /* after-school everywhere else */
    };
    /* Check every minute of an entire week against the intended default timetable. */
    for (int day = 0; day < 7; day++) {
        for (int minute = 0; minute < 1440; minute++) {
            int expected = !(day >= 1 && day <= 5 && minute >= 540 && minute < 930);
            assert(sg_mode(defaults, 2, day, minute) == expected);
        }
    }
    SGWindow overnight = {1320, 120, 1u << 5, 1, 0}; /* Fri 22:00–Sat 02:00 */
    assert(sg_mode(&overnight, 1, 5, 1319) == 0);
    assert(sg_mode(&overnight, 1, 5, 1320) == 1);
    assert(sg_mode(&overnight, 1, 6, 0) == 1);
    assert(sg_mode(&overnight, 1, 6, 119) == 1);
    assert(sg_mode(&overnight, 1, 6, 120) == 0);
    assert(sg_mode(&overnight, 1, 0, 60) == 0);
    overnight.weekdays = 1u << 6; /* also test week wrap */
    assert(sg_mode(&overnight, 1, 0, 119) == 1);
    assert(sg_mode(&overnight, 1, 0, 120) == 0);
    SGWindow invalid = {1440, 120, 1, 1, 0};
    assert(!sg_window_valid(invalid));
    invalid = (SGWindow){100, 100, 1, 1, 0};
    assert(!sg_window_valid(invalid));
    invalid.all_day = 1; assert(sg_window_valid(invalid));
    invalid.weekdays = 0; assert(!sg_window_valid(invalid));
    assert(sg_mode(NULL, 0, 2, 600) == 0);
    assert(sg_accumulate(5, 1, 1, 1, 0, 0) == 6);
    assert(sg_accumulate(5, 1, 0, 1, 0, 0) == 5);
    assert(sg_accumulate(5, 1, 1, 0, 0, 0) == 5);
    assert(sg_accumulate(5, 1, 1, 1, 1, 0) == 5);
    assert(sg_accumulate(5, 1, 1, 1, 0, 1) == 5);
    assert(sg_accumulate(5, 3600, 1, 1, 0, 0) == 5);
    assert(sg_accumulate(5, -1, 1, 1, 0, 0) == 5);
    assert(sg_accumulate(5, NAN, 1, 1, 0, 0) == 5);
    assert(sg_should_block(59.9, 60, 1, 0, 0) == 0);
    assert(sg_should_block(60, 60, 1, 0, 0) == 1);
    assert(sg_should_block(61, 60, 0, 0, 0) == 0);
    assert(sg_should_block(61, 60, 1, 1, 0) == 0);
    assert(sg_should_block(61, 60, 1, 0, 1) == 0);
    assert(sg_should_block(61, 0, 1, 0, 0) == 0);
    assert(sg_should_block(NAN, 60, 1, 0, 0) == 0);
    /* Multiple after-school windows add to a single allowance; school never consumes it. */
    double usage = 0;
    for (int second = 0; second < 120; second++) usage = sg_accumulate(usage, 1, 1, 1, 0, 0);
    for (int second = 0; second < 120; second++) usage = sg_accumulate(usage, 1, 0, 1, 0, 0);
    for (int second = 0; second < 120; second++) usage = sg_accumulate(usage, 1, 1, 1, 0, 0);
    assert(usage == 240);
    puts("PASS: all 10,080 weekly minutes, overnight boundaries, pauses, sleep gaps, and thresholds");
    return 0;
}
