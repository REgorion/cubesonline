package physics

import t "../types"
import "core:math"

AABB :: struct {
    center: t.float3,
    extents: t.float3,
}

get_overlapping :: proc(a_pos, b_pos: t.double3, a, b: AABB) -> (bool, t.float3) {
    a_min : t.double3 = t.double3{
        f64(a.center.x - a.extents.x),
        f64(a.center.y - a.extents.y),
        f64(a.center.z - a.extents.z),
    }
    b_min : t.double3 = t.double3{
        f64(b.center.x - b.extents.x),
        f64(b.center.y - b.extents.y),
        f64(b.center.z - b.extents.z),
    }
    
    b_max : t.double3 = t.double3{
        f64(b.center.x + b.extents.x),
        f64(b.center.y + b.extents.y),
        f64(b.center.z + b.extents.z),
    }
    a_max : t.double3 = t.double3{
        f64(a.center.x + a.extents.x),
        f64(a.center.y + a.extents.y),
        f64(a.center.z + a.extents.z),
    }

    a_min += a_pos
    b_min += b_pos

    a_max += a_pos
    b_max += b_pos

    if a_max.x < b_min.x || a_min.x > b_max.x ||
    a_max.y < b_min.y || a_min.y > b_max.y ||
    a_max.z < b_min.z || a_min.z > b_max.z {
        return false, t.float3{0, 0, 0}
    }

    overlap_x := f32(min(a_max.x - b_min.x, b_max.x - a_min.x))
    overlap_y := f32(min(a_max.y - b_min.y, b_max.y - a_min.y))
    overlap_z := f32(min(a_max.z - b_min.z, b_max.z - a_min.z))

    return true, t.float3{overlap_x, overlap_y, overlap_z} 
}

get_swept :: proc(a_velocity: t.float3, a_pos, b_pos: t.double3, a, b: AABB) -> (bool, f32, t.float3) {
    a_min := t.double3{f64(a.center.x - a.extents.x), f64(a.center.y - a.extents.y), f64(a.center.z - a.extents.z)} + a_pos
    a_max := t.double3{f64(a.center.x + a.extents.x), f64(a.center.y + a.extents.y), f64(a.center.z + a.extents.z)} + a_pos

    b_min := t.double3{f64(b.center.x - b.extents.x), f64(b.center.y - b.extents.y), f64(b.center.z - b.extents.z)} + b_pos
    b_max := t.double3{f64(b.center.x + b.extents.x), f64(b.center.y + b.extents.y), f64(b.center.z + b.extents.z)} + b_pos

    entry := t.float3{0, 0, 0}
    exit  := t.float3{0, 0, 0}

    for axis in 0..<3 {
        v := a_velocity[axis]
        if v > 0 {
            entry[axis] = (f32(b_min[axis] - a_max[axis]) / v)
            exit[axis]  = (f32(b_max[axis] - a_min[axis]) / v)
        } else if v < 0 {
            entry[axis] = (f32(b_max[axis] - a_min[axis]) / v)
            exit[axis]  = (f32(b_min[axis] - a_max[axis]) / v)
        } else {
            if a_max[axis] < b_min[axis] || a_min[axis] > b_max[axis] {
                return false, 1.0, t.float3{0,0,0}
            }
            entry[axis] = math.NEG_INF_F32
            exit[axis]  = math.INF_F32
        }
    }

    entry_time := max(entry.x, max(entry.y, entry.z))
    exit_time  := min(exit.x, min(exit.y, exit.z))

    if entry_time > exit_time || entry_time < 0.0 || entry_time > 1.0 {
        return false, 1.0, t.float3{0,0,0}
    }

    // Определяем нормаль столкновения
    normal := t.float3{0,0,0}
    if entry_time == entry.x {
        normal.x = a_velocity.x > 0 ? -1 : 1
    } else if entry_time == entry.y {
        normal.y = a_velocity.y > 0 ? -1 : 1 
    } else {
        normal.z = a_velocity.z > 0 ? -1 : 1
    }

    return true, entry_time, normal
}