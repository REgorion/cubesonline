package world

import "base:runtime"
import t "../types"
import list "core:container/intrusive/list"
import q "core:container/queue"
import rl "vendor:raylib"
import "core:log"
import math "core:math"

WORLD_HEIGHT     : i32 : 8
SECTION_SIZE       : i32 : 16
SECTION_SIZE_CUBED : i32 : SECTION_SIZE * SECTION_SIZE * SECTION_SIZE

chunkId :: u16

Section :: struct {
    position:   t.int3,
    blocks:     []u16,
    palette:    []u32,

    hasModel: bool,
    mesh: ^rl.Mesh,
    model: rl.Model,
}

Chunk :: struct {
    id:       chunkId,
    sections: []Section,
    position: t.int2,
}

World :: struct {
    active_chunks:          []chunkId,

    draw_distance:          i32,
    center:                 t.int2,

    previous_center:        t.int2,
    previous_draw_dist:     i32,
}

Chunk_To_Update_Node :: struct {
    using node: list.Node,
    distance: i32,
    priority: u8,
    chunk_id: chunkId,
}

free_chunks: q.Queue(chunkId)

all_chunks: [dynamic]Chunk
world: World

chunks_to_update: q.Queue(chunkId)

// ===== Local coordinates and indexes
local_block_index_to_coord :: proc (index: i32) -> t.int3 {
    return t.int3 {
        index % SECTION_SIZE,
        index / (SECTION_SIZE * SECTION_SIZE),
        index / SECTION_SIZE % SECTION_SIZE,
    }
}

local_coord_to_block_index :: proc (coord: t.int3) -> i32 {
    return coord.y * SECTION_SIZE * SECTION_SIZE + coord.z * SECTION_SIZE + coord.x;
}

is_local_coord_in_bounds :: proc (coord: t.int3) -> bool {
    return  coord.x >= 0 && coord.x < SECTION_SIZE &&
    coord.y >= 0 && coord.y < SECTION_SIZE &&
    coord.z >= 0 && coord.z < SECTION_SIZE
}

is_local_index_in_bounds :: proc (index: i32) -> bool {
    return index >= 0 && index < SECTION_SIZE_CUBED
}

local_coord_to_global_coord :: proc (section: Section, coord: t.int3) -> t.int3 {
    return section.position * SECTION_SIZE + coord
}

// ===== Chunk coordinates and indexes
chunk_coord_to_index :: proc(world: ^World, coord: t.int2) -> i32 {
    lx := coord.x - (world.center.x - world.draw_distance);
    ly := coord.y - (world.center.y - world.draw_distance);

    if  lx < 0 || lx > 2 * world.draw_distance ||
        ly < 0 || ly > 2 * world.draw_distance {
        
        return -1;
    }

    return ly * (2 * world.draw_distance + 1) + lx
}

is_chunk_in_bounds :: proc(world: ^World, coord: t.int2) -> bool {
    dx := abs(coord.x - world.center.x)
    dy := abs(coord.y - world.center.y)

    return dx <= world.draw_distance && dy <= world.draw_distance
}

// ===== Getting sections in world
get_section_by_coord :: proc(world: ^World, coord: t.int3) -> (ok: bool, section: ^Section) {
    if coord.y < 0 || coord.y >= WORLD_HEIGHT {
        return
    }
    
    chunk_id : chunkId
    ok, chunk_id = get_chunk_by_coord(world, coord.xz)
    
    if !ok {
        return
    }
    
    section = &all_chunks[chunk_id].sections[coord.y]
    return 
}

// ===== Getting chunks in world
get_chunk_by_coord :: proc(world: ^World, coord: t.int2) -> (ok: bool, id: chunkId) {
    index := chunk_coord_to_index(world, coord)
    ok = true
    if index == -1
    {
        ok = false
        return
    }
    if index >= i32(len(world.active_chunks))
    {
        ok = false
        return
    }
    
    id = world.active_chunks[index]
    return
}

// ===== Global coordinated
is_coord_in_bounds :: proc(world: ^World, coord: t.int3) -> bool {
    if coord.y >= WORLD_HEIGHT * SECTION_SIZE || coord.y < 0 {
        return false
    }
    
    chunk_coord := (coord / SECTION_SIZE).xz
    
    return is_chunk_in_bounds(world, chunk_coord)
}

// ===== Get/set blocks in world
get_block :: proc(world: ^World, coord: t.int3) -> u16 {
    if coord.y >= WORLD_HEIGHT * SECTION_SIZE || coord.y < 0
    {
        return 0
    }

    xf := f32(coord.x) / f32(SECTION_SIZE)
    yf := f32(coord.z) / f32(SECTION_SIZE)

    x : i32
    y : i32

    x = i32(math.floor_f32(xf))
    y = i32(math.floor_f32(yf))
    chunk_coord := t.int2{x, y}
    //(coord / SECTION_SIZE).xz

    ok, chunk_id := get_chunk_by_coord(world, chunk_coord)
    if !ok
    {
        return 0
    }

    section_index := coord.y / SECTION_SIZE

    chunk := all_chunks[chunk_id]
    local_coord := coord - t.int3{chunk_coord.x, 0, chunk_coord.y} * SECTION_SIZE
    local_coord.y = coord.y % SECTION_SIZE

    block_index := local_coord_to_block_index(local_coord)
    blocks := chunk.sections[section_index].blocks

    if block_index < 0 || block_index >= i32(len(blocks))
    {
        log.logf(.Info, "Block index %v, coord %v, chunk coord %v", block_index, coord, chunk_coord)
        return 0
    }

    return blocks[block_index]
}

set_block :: proc(world: ^World, coord: t.int3, block_id: u16) -> bool {
    if coord.y >= WORLD_HEIGHT * SECTION_SIZE || coord.y < 0
    {
        return false
    }

    xf := f32(coord.x) / f32(SECTION_SIZE)
    yf := f32(coord.z) / f32(SECTION_SIZE)

    x : i32
    y : i32

    x = i32(math.floor_f32(xf))
    y = i32(math.floor_f32(yf))
    chunk_coord := t.int2{x, y}

    ok, chunk_id := get_chunk_by_coord(world, chunk_coord)
    if !ok
    {
        return false
    }

    section_index := coord.y / SECTION_SIZE

    chunk := &all_chunks[chunk_id]
    local_coord := coord - t.int3{chunk_coord.x, 0, chunk_coord.y} * SECTION_SIZE
    local_coord.y = coord.y % SECTION_SIZE

    block_index := local_coord_to_block_index(local_coord)
    chunk.sections[section_index].blocks[block_index] = block_id
    
    return true
}

set_block_and_get_section :: proc(world: ^World, coord: t.int3, block_id: u16) -> (bool, ^Section) {
    xf := f32(coord.x) / f32(SECTION_SIZE)
    yf := f32(coord.z) / f32(SECTION_SIZE)

    x : i32
    y : i32

    x = i32(math.floor_f32(xf))
    y = i32(math.floor_f32(yf))
    chunk_coord := t.int2{x, y}

    ok, chunk_id := get_chunk_by_coord(world, chunk_coord)
    if !ok
    {
        return false, nil
    }

    section_index := coord.y / SECTION_SIZE

    chunk := &all_chunks[chunk_id]
    local_coord := coord - t.int3{chunk_coord.x, 0, chunk_coord.y} * SECTION_SIZE
    local_coord.y = coord.y % SECTION_SIZE
    section := &chunk.sections[section_index]

    block_index := local_coord_to_block_index(local_coord)
    section.blocks[block_index] = block_id
    
    return true, section
}

// ===== Pooling
create_new_chunks :: proc(count: i32, allocator: runtime.Allocator) -> (chunks: []Chunk) {
    if count <= 0 {return}

    low := len(all_chunks)
    high := len(all_chunks)

    for i in 0..<count {
        sections := new([WORLD_HEIGHT]Section)
        chunk_id := chunkId(len(all_chunks))

        chunk := Chunk {
            id = chunk_id,
            sections = sections[:],
        }

        append_elem(&all_chunks, chunk)

        for j in 0..<WORLD_HEIGHT {
            blocks := new([SECTION_SIZE_CUBED]u16)
            sections[j] = Section {
                blocks = blocks[:]
            }
        }

        high += 1
    }

    chunks = all_chunks[low:high]

    return
}

get_chunk_from_pool :: proc() -> (id: chunkId) {
    if q.len(free_chunks) == 0
    {
        chunks := create_new_chunks(8, context.allocator)
        
        id = chunks[0].id
        
        for i in 1..<len(chunks)
        {
            q.push_back(&free_chunks, chunks[i].id)
        }
    }
    else
    {
        id = q.pop_front(&free_chunks)
    }
    
    return
}

return_chunk_to_pool :: proc(id: chunkId) {
    q.push_back(&free_chunks, id)
}

// ===== World loading

update_active_chunks :: proc(world: ^World, allocator: runtime.Allocator) {
    chunks_count : i32 = i32(world.draw_distance * 2 + 1) * i32(world.draw_distance * 2 + 1)
    
    required : map[t.int2]struct{}
    defer delete(required)

    for z := -world.draw_distance; z <= world.draw_distance; z += 1 
    {
        for x := -world.draw_distance; x <= world.draw_distance; x += 1 
        {
            required[t.int2{i32(x), i32(z)} + world.center] = {}
        }
    }
    
    if all_chunks == nil 
    {
        all_chunks = make_dynamic_array_len_cap([dynamic]Chunk, 0, chunks_count, allocator)
    }

    // CREATING NEW CHUNKS
    all_chunks_count : i32 = i32(len(all_chunks))
    if all_chunks_count < chunks_count 
    {
        diff := chunks_count - all_chunks_count
        create_new_chunks(diff, context.allocator)
    }
    
    // REMOVING CHUNKS OUT OF BOUNDS
    
    new_chunks := make([]chunkId, chunks_count)

    for i in 0..<len(world.active_chunks) 
    {
        index := world.active_chunks[i]
        chunk := &all_chunks[index]
        
        if is_chunk_in_bounds(world, chunk.position) 
        {
            new_index := chunk_coord_to_index(world, chunk.position)
            new_chunks[new_index] = index
            delete_key(&required, chunk.position)
        }   
        else
        {
            return_chunk_to_pool(chunk.id)
        }
    }
    
    // ADDING NEW CHUNKS
    added : map[chunkId]struct{}
    defer delete(added)
    
    for pos in required 
    {
        new_index := chunk_coord_to_index(world, pos)
        if new_index < 0 {continue}
        
        new_chunk_id := get_chunk_from_pool()
        
        // SETTING NEW POSITION
        chunk := &all_chunks[new_chunk_id]
        chunk.position = pos
        
        // GENERATION
        for i in 0..<SECTION_SIZE_CUBED * WORLD_HEIGHT
        {
            section_index := i / SECTION_SIZE_CUBED
            section := &all_chunks[new_chunk_id].sections[section_index]
            
            if section.hasModel {
                model := section.model
                rl.UnloadModel(model)
                section.hasModel = false
            }
            
            block_index := i % SECTION_SIZE_CUBED
            
            section.position = t.int3{pos.x, section_index, pos.y}
            block_coord := local_block_index_to_coord(block_index)
            glob_coord := local_coord_to_global_coord(section^, block_coord)
            
            if glob_coord.y > 15 {
                section.blocks[block_index] = 0
            }
            else {
                section.blocks[block_index] = 1
            }
        }
        new_chunks[new_index] = chunk.id
        added[chunk.id] = {}
    }
    
    // GETTING NEIGHBOURING CHUNKS TO NEWLY ADDED
    tempAdded : map[chunkId]struct{}
    
    for id in added
    {
        tempAdded[id] = {}
    }
    
    for id in tempAdded
    {
        ok : bool
        neighbor_id : chunkId
        
        chunk := all_chunks[id]
        
        ok, neighbor_id = get_chunk_by_coord(world, chunk.position + t.int2{1, 0})
        if ok { added[neighbor_id] = {} }
        
        ok, neighbor_id = get_chunk_by_coord(world, chunk.position + t.int2{-1, 0})
        if ok { added[neighbor_id] = {} }
        
        ok, neighbor_id = get_chunk_by_coord(world, chunk.position + t.int2{0, 1})
        if ok { added[neighbor_id] = {} }
        
        ok, neighbor_id = get_chunk_by_coord(world, chunk.position + t.int2{0, -1})
        if ok { added[neighbor_id] = {} }
    }
    delete(tempAdded)
    
    if world.active_chunks != nil {
        delete(world.active_chunks)
    }
    world.active_chunks = new_chunks
    
    // SORTING NEWLY ADDED CHUNKS TO UPDATE THEM LATER IN SEQUENCE

    for chunk_id in added
    {
        chunk := all_chunks[chunk_id]
        diff := chunk.position - world.center
        dist := diff.x * diff.x + diff.y * diff.y

        q.append(&chunks_to_update, chunk_id)
    }
}