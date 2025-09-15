package chunk_renderer

import rl "vendor:raylib"
import "core:fmt"
import "core:log"
import "core:time"
import "core:math"
import t "../types"
import w "../world"

// CONSTS
ATLAS_SIZE       : i32 : 2
ATLAS_ONE        : f32 : 1.0 / f32(ATLAS_SIZE)

// STRUCTS
VertexData :: struct {
    position:   t.float3,
    normal:     t.float3,
    color:      t.color32,
    uv:         t.float2
}

// CACHED DATA
vertices := [24]t.float3 {
// top
    t.float3{0, 1, 0},
    t.float3{0, 1, 1},
    t.float3{1, 1, 1},
    t.float3{1, 1, 0},
    // bottom
    t.float3{0, 0, 0},
    t.float3{1, 0, 0},
    t.float3{1, 0, 1},
    t.float3{0, 0, 1},
    // left
    t.float3{0, 0, 1},
    t.float3{0, 1, 1},
    t.float3{0, 1, 0},
    t.float3{0, 0, 0},
    // right
    t.float3{1, 0, 0},
    t.float3{1, 1, 0},
    t.float3{1, 1, 1},
    t.float3{1, 0, 1},
    // front
    t.float3{1, 0, 1},
    t.float3{1, 1, 1},
    t.float3{0, 1, 1},
    t.float3{0, 0, 1},
    // back
    t.float3{0, 0, 0},
    t.float3{0, 1, 0},
    t.float3{1, 1, 0},
    t.float3{1, 0, 0}
}

normals := [6]t.float3 {
// top
    t.float3{0, 1, 0},
    // bottom
    t.float3{0, -1, 0},
    // left
    t.float3{-1, 0, 0},
    // right
    t.float3{1, 0, 0},
    // front
    t.float3{0, 0, 1},
    // back
    t.float3{0, 0, -1},
}

int_normals := [6]t.int3 {
// top
    t.int3{0, 1, 0},
    // bottom
    t.int3{0, -1, 0},
    // left
    t.int3{-1, 0, 0},
    // right
    t.int3{1, 0, 0},
    // front
    t.int3{0, 0, 1},
    // back
    t.int3{0, 0, -1},
}

vertex_data   : [w.SECTION_SIZE_CUBED * 6 * 4]VertexData
triangle_data : [w.SECTION_SIZE_CUBED * 6 * 6]u32

sections : [27]^w.Section

get_section_by_offset :: #force_inline proc(offset: t.int3) -> ^w.Section
{
    o := offset + t.int3{1, 1, 1}
    
    i := t.mod(o.x, 3) + o.z * 3 + o.y * 9
    if i >= len(sections) || i < 0
    {
        return sections[13]
    }
    
    return sections[i]
}

get_block :: proc(local_pos: t.int3) -> u16
{
    section : ^w.Section
    new_block_pos : t.int3 = local_pos
    
    if w.is_local_coord_in_bounds(local_pos)
    {
        section = sections[13]
    }
    else
    {
        x : i32
        y : i32
        z : i32
        
        if local_pos.x > 15 {
            x = 1
        }
        else if local_pos.x < 0 {
            x = -1
        }
        
        if local_pos.y > 15 {
            y = 1
        }
        else if local_pos.y < 0 {
            y = -1
        }
        
        if local_pos.z > 15 {
            z = 1
        }
        else if local_pos.z < 0 {
            z = -1
        }
        
        section = get_section_by_offset(t.int3{x, y, z})
        
        new_block_pos = t.int3{
            t.mod(local_pos.x, w.SECTION_SIZE),
            t.mod(local_pos.y, w.SECTION_SIZE),
            t.mod(local_pos.z, w.SECTION_SIZE),
        }
    }
    
    if section == nil {
        return 0
    }
    
    block_index := w.local_coord_to_block_index(new_block_pos)
    if block_index < 0 || block_index >= w.SECTION_SIZE_CUBED {
        return 0
    }
    
    return section.blocks[block_index]
}

get_mesh_for_section :: proc (section: ^w.Section, world: ^w.World, mesh: ^rl.Mesh) -> bool {
    if i32(len(section.blocks)) != w.SECTION_SIZE_CUBED
    {
        return false
    }
    
    current_vertex_index    : u32
    current_triangle_index  : u32
    
    section_position : t.int3 = section.position * w.SECTION_SIZE
    
    visible_faces_count : i32
    
    for i in 0..<27 {
        
        if i == 13 {
            sections[13] = section
        }
        
        y   : i32 = i32(i) / 9
        rem : i32 = i32(i) % 9
        z   : i32 = rem / 3
        x   : i32 = rem % 3
        offset := t.int3{x - 1, y - 1, z - 1}
        
        ok, section := w.get_section_by_coord(world, offset + section.position)
        
        if ok {
            sections[i] = section
        }
        else {
            sections[i] = nil
        }
    }

    for i in 0..<w.SECTION_SIZE_CUBED 
    {
        coord           : t.int3  = w.local_block_index_to_coord(i)
        blockIndex      : u16   = section.blocks[i]
        isTransparent   : bool  = false
        
        if blockIndex == 0 {continue}
        
        // FACE CULLING
        for j in 0..<6 {
            face : u8 = 1 << u8(j)
            neighborCoords  : t.int3 = coord + int_normals[j]
            neighborIndex   : i32
            neighborBlockId : u16

            neighborBlockId = get_block(neighborCoords)

            // FIXME
            isNeighborTransparent := false
            
            if neighborBlockId != 0 {
                continue
            }

            visible_faces_count += 1

            texture_index : u32 = u32(blockIndex)

            is_flipped := generate_face_vertices(
                world,
                coord,
                section_position,
                u8(j),
                current_vertex_index,
                texture_index,
                vertex_data[:])

            generate_face_triangles(
                current_vertex_index,
                current_triangle_index,
                is_flipped,
                triangle_data[:])
            
            current_vertex_index += 4
            current_triangle_index += 6
        }
    }

    // MESH CREATION
    mesh.vertexCount = i32(current_vertex_index)
    mesh.triangleCount = i32(current_triangle_index / 3)
    
    mesh.vertices = transmute([^]f32)(rl.MemAlloc(u32(size_of(t.float3) * mesh.vertexCount)))
    mesh.normals = transmute([^]f32)(rl.MemAlloc(u32(size_of(t.float3) * mesh.vertexCount)))
    mesh.colors = transmute([^]u8)(rl.MemAlloc(u32(size_of(t.color32) * mesh.vertexCount)))
    mesh.texcoords = transmute([^]f32)(rl.MemAlloc(u32(size_of(t.float2) * mesh.vertexCount)))
    mesh.indices = transmute([^]u16)(rl.MemAlloc(u32(size_of(u16) * current_triangle_index)))
    
    for i in 0..<mesh.vertexCount {
        vertex := vertex_data[i]
        
        mesh.vertices[i * 3 + 0] = vertex.position.x
        mesh.vertices[i * 3 + 1] = vertex.position.y
        mesh.vertices[i * 3 + 2] = vertex.position.z
        
        mesh.normals[i * 3 + 0] = vertex.normal.x
        mesh.normals[i * 3 + 1] = vertex.normal.y
        mesh.normals[i * 3 + 2] = vertex.normal.z
        
        mesh.colors[i * 4 + 0] = vertex.color.r
        mesh.colors[i * 4 + 1] = vertex.color.g
        mesh.colors[i * 4 + 2] = vertex.color.b
        mesh.colors[i * 4 + 3] = vertex.color.a
        
        mesh.texcoords[i * 2 + 0] = vertex.uv.x
        mesh.texcoords[i * 2 + 1] = vertex.uv.y
    }
    
    for i in 0..<current_triangle_index {
        mesh.indices[i] = u16(triangle_data[i])
    }

    return true
}

generate_face_vertices :: #force_inline proc (
    world: ^w.World,
    position: t.int3,
    chunk_position: t.int3,
    face_index: u8,
    array_index: u32,
    texture_index: u32,
    vertex_data: []VertexData) -> (isFlipped: bool) {
    
    normal := normals[face_index]
    uvOffset := t.float2{
        f32(texture_index % u32(ATLAS_SIZE)),
        f32(u32(ATLAS_SIZE) - (texture_index / u32(ATLAS_SIZE)) - 1)} / f32(ATLAS_SIZE)
    
    pos1 : t.float3 = vertices[face_index * 4 + 0]
    pos2 : t.float3 = vertices[face_index * 4 + 1]
    pos3 : t.float3 = vertices[face_index * 4 + 2]
    pos4 : t.float3 = vertices[face_index * 4 + 3]
    
    color1 : t.color32 = get_face_ao(world, face_index, position, pos1)
    color2 : t.color32 = get_face_ao(world, face_index, position, pos2)
    color3 : t.color32 = get_face_ao(world, face_index, position, pos3)
    color4 : t.color32 = get_face_ao(world, face_index, position, pos4)
    
    float_pos :t.float3 = t.float3 {
        f32(position.x),
        f32(position.y),
        f32(position.z),
    }
    vertex_data[array_index + 0] = {
        position = pos1 + float_pos,
        normal = normal,
        uv = t.float2{uvOffset.x + 0, uvOffset.y + 0},
        color = color1
    }

    vertex_data[array_index + 1] = {
        position = pos2 + float_pos,
        normal = normal,
        uv = t.float2{uvOffset.x + 0, uvOffset.y + ATLAS_ONE},
        color = color2
    }

    vertex_data[array_index + 2] = {
        position = pos3 + float_pos,
        normal = normal,
        uv = t.float2{uvOffset.x + ATLAS_ONE, uvOffset.y + ATLAS_ONE},
        color = color3
    }

    vertex_data[array_index + 3] = {
        position = pos4 + float_pos,
        normal = normal,
        uv = t.float2{uvOffset.x + ATLAS_ONE, uvOffset.y + 0},
        color = color4
    }
    
    return (color1.r + color3.r) > (color2.r + color4.r);
}

get_face_ao :: #force_inline proc(world: ^w.World, face_index: u8, local_position: t.int3, vertex_position:t.float3) ->t.color32 {
    corner : t.int3
    side1 : t.int3
    side2 : t.int3
    opposite : t.int3
    
    switch face_index {
        case 0: // Top (Y+)
            corner      = t.int3{vertex_position.x > 0.5 ? 1 : -1, 1, vertex_position.z > 0.5 ? 1 : -1}
            side1        = t.int3{corner.x, 1, 0}
            side2       = t.int3{0, 1, corner.z}
            opposite    = t.int3{0, 1, 0}
            break
        case 1: // Top (Y+)
            corner      = t.int3{vertex_position.x > 0.5 ? 1 : -1, -1, vertex_position.z > 0.5 ? 1 : -1}
            side1        = t.int3{corner.x, -1, 0}
            side2       = t.int3{0, -1, corner.z}
            opposite    = t.int3{0, -1, 0}
            break
        case 2: // Left (X-)
            corner      = t.int3{-1, vertex_position.y > 0.5 ? 1 : -1, vertex_position.z > 0.5 ? 1 : -1}
            side1        = t.int3{-1, corner.y, 0}
            side2       = t.int3{-1, 0, corner.z}
            opposite    = t.int3{-1, 0, 0}
            break
        case 3: // Right (X+)
            corner      = t.int3{1, vertex_position.y > 0.5 ? 1 : -1, vertex_position.z > 0.5 ? 1 : -1}
            side1        = t.int3{1, corner.y, 0}
            side2       = t.int3{1, 0, corner.z}
            opposite    = t.int3{1, 0, 0}
            break
        case 4: // Front (Z+)
            corner      = t.int3{vertex_position.x > 0.5 ? 1 : -1, vertex_position.y > 0.5 ? 1 : -1, 1}
            side1        = t.int3{corner.x, 0, 1}
            side2       = t.int3{0, corner.y, 1}
            opposite    = t.int3{0, 0, 1}
            break
        case 5: // Back (Z-)
            corner      = t.int3{vertex_position.x > 0.5 ? 1 : -1, vertex_position.y > 0.5 ? 1 : -1, -1}
            side1        = t.int3{corner.x, 0, -1}
            side2       = t.int3{0, corner.y, -1}
            opposite    = t.int3{0, 0, -1}
            break
        case:
            return t.color32{255, 15, 0, 255}
    }
    
    block1   : u16 = get_block(local_position + side1)
    block2   : u16 = get_block(local_position + side2)
    block3   : u16 = get_block(local_position + corner)
    block4   : u16 = get_block(local_position + opposite)
    
    occlusion : u8
    
    if (block1 != 0){
        occlusion += u8(85)
    }
    
    if (block2 != 0){
        occlusion += u8(85)
    }

    if (block3 != 0){
        occlusion += u8(85)
    }

    if (block4 != 0){
        occlusion += u8(85)
    }
    
    occlusion = 255 - occlusion
    
    return t.color32 {occlusion, 255, 0, 255}
}

generate_face_triangles :: #force_inline proc (
        array_index : u32,
        triangle_index : u32,
        is_flipped : bool,
        triangles : []u32) 
{

    if is_flipped
    {
        triangles[triangle_index + 0] = array_index + 0
        triangles[triangle_index + 1] = array_index + 1
        triangles[triangle_index + 2] = array_index + 2

        triangles[triangle_index + 3] = array_index + 0
        triangles[triangle_index + 4] = array_index + 2
        triangles[triangle_index + 5] = array_index + 3
    }
    else
    {

        triangles[triangle_index + 0] = array_index + 3
        triangles[triangle_index + 1] = array_index + 0
        triangles[triangle_index + 2] = array_index + 1

        triangles[triangle_index + 3] = array_index + 3
        triangles[triangle_index + 4] = array_index + 1
        triangles[triangle_index + 5] = array_index + 2
    }
    
}