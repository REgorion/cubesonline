package physics

import t "../types"
import "core:math"
import "core:log"
import "core:math/linalg"
import "base:runtime"
import w "../world"
import "../entity"

GRAVITY : f32 : -32

AABB :: struct {
    center: t.float3,
    extents: t.float3,
}

WorldOverlapResult :: struct {
    count: i32,
    coords: [dynamic]t.int3,
    block_ids: [dynamic]u16,
}

broadphase: [dynamic]t.int3
block_overlaps: [dynamic]t.int3

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

overlap_world :: proc(world: ^w.World, pos: t.double3, aabb: AABB) -> (result: WorldOverlapResult) {
    min := t.double3{
        pos.x + f64(aabb.center.x - aabb.extents.x),
        pos.y + f64(aabb.center.y - aabb.extents.y),
        pos.z + f64(aabb.center.z - aabb.extents.z),
    }
    max := t.double3{
        pos.x + f64(aabb.center.x + aabb.extents.x),
        pos.y + f64(aabb.center.y + aabb.extents.y),
        pos.z + f64(aabb.center.z + aabb.extents.z),
    }

    min_block := t.int3{ i32(math.floor(min.x)), i32(math.floor(min.y)), i32(math.floor(min.z)) }
    max_block := t.int3{ i32(math.floor(max.x)), i32(math.floor(max.y)), i32(math.floor(max.z)) }
    
    diff := (max_block - min_block) + t.int3{1, 1, 1}
    max_cap := diff.x * diff.y * diff.z

    result = {
        count = 0,
        coords = make([dynamic]t.int3, 0, max_cap),
        block_ids = make([dynamic]u16, 0, max_cap),
    }
    
    for z := min_block.z; z <= max_block.z; z += 1 {
        for y := min_block.y; y <= max_block.y; y += 1 {
            for x := min_block.x; x <= max_block.x; x += 1 {
                block_pos := t.int3{x,y,z}
                block_id  := w.get_block(world, block_pos)
                if block_id != 0 {
                    result.count += 1
                    append(&result.coords, block_pos)
                    append(&result.block_ids, block_id)
                    append(&block_overlaps, block_pos)
                }
            }
        }
    }
    
    return
}

slide_entity_in_world :: proc(world: ^w.World, entity: ^entity.Entity, entity_aabb: AABB) -> (remaining_slide, slide_normal: t.float3) {
    using entity
    
    delta := entity.velocity * t.TICK_TIME

    candidates := make([dynamic]t.int3, 0, 64)
    candidates_count := get_broadphase_blocks(world, entity_aabb, entity.position, delta, &candidates)
    collided := false

    min_time : f32 = 2
    min_normal : t.float3

    for i in 0..<candidates_count {
        block_aabb := AABB {
            center = {0.5, 0.5, 0.5},
            extents = {0.5, 0.5, 0.5},
        }
        block_pos := t.int3_to_double3(candidates[i])
        collide, time, normal := get_swept(delta, entity.position, block_pos, entity_aabb, block_aabb)

        if !collide {continue}

        collided = true

        if time < min_time {
            min_time = time
            min_normal = normal
        }
    }

    if (collided) {
        move := delta * min_time
        log.logf(.Info, "Correction is: %v", move)
        entity.position += t.float3_to_double3(move + min_normal * 0.001)

        remaining := delta * (1.0 - min_time)
        dot := linalg.vector_dot(min_normal, remaining)
        slide := remaining - min_normal * dot
        
        mask := t.float3{1, 1, 1} - linalg.abs(min_normal)
        entity.velocity *= mask
        log.logf(.Info, "New velocity is: %v", entity.velocity)

        return slide, min_normal
    }
    else {
        entity.position += t.float3_to_double3(delta)
        return 0, t.float3{}
    }
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

get_broadphase_blocks :: proc(world: ^w.World, aabb: AABB, pos: t.double3, delta: t.float3, candidates: ^[dynamic]t.int3) -> i32 {
    min := t.double3{
        pos.x + f64(aabb.center.x - aabb.extents.x),
        pos.y + f64(aabb.center.y - aabb.extents.y),
        pos.z + f64(aabb.center.z - aabb.extents.z),
    }
    max := t.double3{
        pos.x + f64(aabb.center.x + aabb.extents.x),
        pos.y + f64(aabb.center.y + aabb.extents.y),
        pos.z + f64(aabb.center.z + aabb.extents.z),
    }

    corrected_delta := delta * 1.0
    if corrected_delta.x > 0 { max.x += f64(corrected_delta.x) } else { min.x += f64(corrected_delta.x) }
    if corrected_delta.y > 0 { max.y += f64(corrected_delta.y) } else { min.y += f64(corrected_delta.y) }
    if corrected_delta.z > 0 { max.z += f64(corrected_delta.z) } else { min.z += f64(corrected_delta.z) }

    min_block := t.int3{ i32(math.floor(min.x)), i32(math.floor(min.y)), i32(math.floor(min.z)) }
    max_block := t.int3{ i32(math.floor(max.x)), i32(math.floor(max.y)), i32(math.floor(max.z)) }
    
    for z := min_block.z; z <= max_block.z; z += 1 {
        for y := min_block.y; y <= max_block.y; y += 1 {
            for x := min_block.x; x <= max_block.x; x += 1 {
                block_pos := t.int3{x,y,z}
                if w.get_block(world, block_pos) != 0 {
                    append_elem(candidates, block_pos)
                    append_elem(&broadphase, block_pos)
                }
            }
        }
    }

    return i32(len(candidates))
}