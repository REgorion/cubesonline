package types

import "core:time"
import "core:log"

// TYPES
float3 :: [3]f32
float2 :: [2]f32
double3:: [3]f64
double2:: [2]f64
int3 :: [3]i32
int2 :: [2]i32
color32 :: [4]u8

stopwatch: [4]time.Stopwatch

mod :: proc(a, b: i32) -> i32 {
    m := a % b
    if m < 0 {
        m += b
    }
    return m
}


start_stopwatch :: proc(index: i32) {
    time.stopwatch_start(&stopwatch[index])
}

pause_stopwatch :: proc(index: i32) {
    time.stopwatch_stop(&stopwatch[index])
}

stop_stopwatch :: proc(index: i32, label: string) {
    time.stopwatch_stop(&stopwatch[index])
    log.logf(.Info, "%v: %v", label, time.stopwatch_duration(stopwatch[index]))
    time.stopwatch_reset(&stopwatch[index])
}
