package types

import "core:time"
import "core:log"
import math "core:math"

// CONSTANTS
TICKRATE :: 20
TICK_TIME : f32 : 1.0 / f32(TICKRATE)

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

mod_f32 :: proc(a, b: f32) -> f32 {
    m := math.mod_f32(a, b)
    if m < 0 {
        m += b
    }
    return m
}

double3_to_float3 :: #force_inline proc(a: double3) -> float3 {
    return {
        f32(a.x),
        f32(a.y),
        f32(a.z),
    }
}

float3_to_double3 :: #force_inline proc(a: float3) -> double3 {
    return {
        f64(a.x),
        f64(a.y),
        f64(a.z),
    }
}

int3_to_float3 :: #force_inline proc(a: int3) -> float3 {
    return {
        f32(a.x),
        f32(a.y),
        f32(a.z),
    }
}

int3_to_double3 :: #force_inline proc(a: int3) -> double3 {
    return {
        f64(a.x),
        f64(a.y),
        f64(a.z),
    }
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
