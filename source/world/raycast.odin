package world

import "core:math"
import "core:math/linalg"
import "../blocks"
import t "../types"

RaycastResult :: struct {
    hit : bool,
    world_pos : t.int3,
    face : blocks.Face,
    normal : t.int3,
    pos : t.double3,
    distance : f64,
    origin : t.double3,
}

raycast :: proc(world: ^World, origin: t.double3, dir: t.double3, ray_length: f64) -> RaycastResult {
// Результат по умолчанию (нет попадания)
    result: RaycastResult = RaycastResult{
        hit = false,
        world_pos = t.int3{},
        pos = origin,
        distance = 0.0,
        origin = origin,
    }

    // Нормализуем направление и определяем шаг по осям
    direction := linalg.vector_normalize(dir)
    dir_x_sqr := direction.x * direction.x
    dir_y_sqr := direction.y * direction.y
    dir_z_sqr := direction.z * direction.z

    unit_step: t.double3 = t.double3{
        math.sqrt(1.0 + math.pow(direction.y / direction.x, 2) +
        math.pow(direction.z / direction.x, 2)),
        math.sqrt(1.0 + math.pow(direction.x / direction.y, 2) +
        math.pow(direction.z / direction.y, 2)),
        math.sqrt(1.0 + math.pow(direction.x / direction.z, 2) +
        math.pow(direction.y / direction.z, 2)),
    }

    current_voxel: t.int3 = t.int3{
        auto_cast (math.floor(origin.x)),
        auto_cast (math.floor(origin.y)),
        auto_cast (math.floor(origin.z)),
    }

    delta_dist: t.double3 = unit_step
    step: t.int3
    side_dist: t.double3

    axises := [3]i32 {0, 1, 2}

    step.x = direction.x > 0 ? 1 : -1
    step.y = direction.y > 0 ? 1 : -1
    step.z = direction.z > 0 ? 1 : -1

    voxel_pos := t.double3 {
        auto_cast current_voxel.x,
        auto_cast current_voxel.y,
        auto_cast current_voxel.z,
    }

    for a in axises {
        if direction[a] < 0 {
            side_dist[a] = ((origin[a] - (voxel_pos[a])) * delta_dist[a])
        }
        else {
            side_dist[a] = (((voxel_pos[a] + 1) - origin[a]) * delta_dist[a])
        }
    }

    distance: f64 = 0.0
    last_axis: t.int3

    for distance < ray_length {
        if side_dist.x < side_dist.y {
            if side_dist.x < side_dist.z {
                current_voxel.x += step.x
                distance = side_dist.x
                side_dist.x += delta_dist.x

                last_axis = t.int3{}
                last_axis.x = step.x
            }
            else {
                current_voxel.z += step.z
                distance = side_dist.z
                side_dist.z += delta_dist.z

                last_axis = t.int3{}
                last_axis.z = step.z
            }
        }
        else {
            if side_dist.y < side_dist.z {
                current_voxel.y += step.y
                distance = side_dist.y
                side_dist.y += delta_dist.y

                last_axis = t.int3{}
                last_axis.y = step.y
            }
            else {
                current_voxel.z += step.z
                distance = side_dist.z
                side_dist.z += delta_dist.z

                last_axis = t.int3{}
                last_axis.z = step.z
            }
        }

        // Проверяем границы мира
        if !is_coord_in_bounds(world, current_voxel) {
            break
        }

        // FIXME
        is_solid := get_block(world, current_voxel) != 0
        if is_solid {
            pos := origin + direction * distance

            face : blocks.Face

            switch last_axis {
            case {0, -1, 0}:
                face = blocks.Face.Top
            case {0, 1, 0}:
                face = blocks.Face.Bottom
            case {-1, 0, 0}:
                face = blocks.Face.Right
            case {1, 0, 0}:
                face = blocks.Face.Left
            case {0, 0, -1}:
                face = blocks.Face.Front
            case {0, 0, -1}:
                face = blocks.Face.Back
            }

            result.hit = true
            result.world_pos = current_voxel
            result.pos = pos
            result.distance = distance
            result.origin = origin
            result.face = face
            result.normal = -last_axis
            return result
        }
    }

    return result
}