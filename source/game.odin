/*
This file is the starting point of your game.

Some important procedures are:
- game_init_window: Opens the window
- game_init: Sets up the game state
- game_update: Run once per frame
- game_should_close: For stopping your game when close button is pressed
- game_shutdown: Shuts down game and frees memory
- game_shutdown_window: Closes window

The procs above are used regardless if you compile using the `build_release`
script or the `build_hot_reload` script. However, in the hot reload case, the
contents of this file is compiled as part of `build/hot_reload/game.dll` (or
.dylib/.so on mac/linux). In the hot reload cases some other procedures are
also used in order to facilitate the hot reload functionality:

- game_memory: Run just before a hot reload. That way game_hot_reload.exe has a
	pointer to the game's memory that it can hand to the new game DLL.
- game_hot_reloaded: Run after a hot reload so that the `g` global
	variable can be set to whatever pointer it was in the old DLL.

NOTE: When compiled as part of `build_release`, `build_debug` or `build_web`
then this whole package is just treated as a normal Odin package. No DLL is
created.
*/

package game

import rl "vendor:raylib"
import w "world"
import list "core:container/intrusive/list"
import rend "chunk_renderer"
import t "types"
import "core:log"
import "core:mem"
import "core:math"
import "core:math/linalg"
import "core:fmt"
import "core:time"
import q "core:container/queue"
import "entity"

Arena :: mem.Arena

GameState :: struct {
	isWireframeRendering : bool,
	doRaycast : bool,
}

Input :: struct {
	axis : [3]f32,
	jump : bool,
	run : bool,
}

data : [256 * mem.Megabyte]byte
arena : Arena

camera : rl.Camera3D

input : Input
sunDirectionLocation : i32

state : GameState
shader: rl.Shader
texture: rl.Texture2D

version: cstring

world : w.World
stopwatch: time.Stopwatch

start :: proc()
{
	camera.position = {3, 3, 3}
	camera.target = {0, 0, 0}
	camera.up = {0, 1, 0}
	camera.fovy = 80
	camera.projection = .PERSPECTIVE

	texture = rl.LoadTexture("assets/stone.png")
	
	version_ptr := rl.LoadFileText("assets/version.txt")
	version = fmt.caprint(transmute(cstring) version_ptr)
	log.log(.Info, version)
	rl.UnloadFileText(version_ptr)

	// NOTE: Hardcoded glsl 3.0.0
	shaders_folder := "assets/shaders/glsl300"
	chunk_vs := rl.TextFormat("%v/chunk.vert", shaders_folder)
	chunk_fs := rl.TextFormat("%v/chunk.frag", shaders_folder)

	shader = rl.LoadShader(chunk_vs, chunk_fs)

	sunDirection := [3]f32{1.0, 0.75, 0.8}
	atlasSize : f32 = 2.0
	sunDirectionLocation = rl.GetShaderLocation(shader, "sunDirection")
	rl.SetShaderValue(shader, sunDirectionLocation, &sunDirection, rl.ShaderUniformDataType.VEC3)
	rl.SetShaderValue(shader, rl.GetShaderLocation(shader, "atlasSize"), &atlasSize, rl.ShaderUniformDataType.FLOAT)
	rl.SetShaderValueTexture(shader, rl.GetShaderLocation(shader, "texture0"), texture)

	rl.DisableCursor()

	world.draw_distance = 3
	log.logf(.Info, "Mod: %v", t.mod(-1, 16))
}

camera_rot : [3]f32
camera_velocity : [3]f32
camera_rot_speed : f32 = 25.0
camera_speed : f32 = 10.0

_time : f32
accumulator : f32
partial_tick : f32

TICKRATE :: 20
TICK_TIME : f32 : 1.0 / f32(TICKRATE)

ticks : [100]bool
frametimes : [100]f32
frametimes_pos : i32

update :: proc() {
	dt := rl.GetFrameTime()
	update_input()
	
	_time += dt
	accumulator += dt

	ticked := false
	
	for accumulator >= TICK_TIME
	{
		accumulator -= TICK_TIME
		tick()
		ticked = true
	}
	
	partial_tick = f32(accumulator) / f32(TICK_TIME)
	
	frametimes[frametimes_pos] = dt
	ticks[frametimes_pos] = ticked
	
	frametimes_pos = (frametimes_pos + 1) % len(frametimes)

	camera_rot.x = rl.GetMouseDelta().x * camera_rot_speed * dt
	camera_rot.y = rl.GetMouseDelta().y * camera_rot_speed * dt

	camera_velocity = input.axis * dt * camera_speed
	if input.run {
		camera_velocity -= {0, 0, camera_speed * dt}

	}
	else if input.jump {
		camera_velocity += {0, 0, camera_speed * dt}
	}
	
	cam_pos := camera.position.xz / f32(w.SECTION_SIZE)
	world.center = t.int2{i32(cam_pos.x), i32(cam_pos.y)}

	rl.UpdateCameraPro(&camera, camera_velocity, camera_rot, 0)

	if currently_updating != -1 {

		chunk := w.all_chunks[currently_updating]

		for i in 0..<1 {
			last_updated_sector += 1
			if last_updated_sector >= w.WORLD_HEIGHT
			{
				last_updated_sector = -1
				currently_updating = -1
				return
			}

			section := &chunk.sections[last_updated_sector]

			if section.hasModel
			{
				model := section.model
				rl.UnloadModel(model)
				section.hasModel = false
			}

			// -----

			mesh := new(rl.Mesh)
			ok := rend.get_mesh_for_section(section, &world, mesh)

			section.mesh = mesh

			rl.UploadMesh(mesh, false)
			
			section.model = rl.LoadModelFromMesh(mesh^)
			section.hasModel = true
			section.model.materials[0].shader = shader
			rl.SetMaterialTexture(&section.model.materials[0], .ALBEDO, texture)
			// -----
			
		}
	}
}

currently_updating : i32 = -1
last_updated_sector: i32 = -1
tick_n: i32 = 0

tick :: proc()
{
	if world.draw_distance != world.previous_draw_dist || world.center != world.previous_center
	{
		world.previous_draw_dist = world.draw_distance
		world.previous_center = world.previous_center

		w.update_active_chunks(&world, context.allocator)
	}
	
	if tick_n % 300 == 0  && tick_n != 0 {
		world.center.y += 1
	}
	
	tick_n += 1
 
	if currently_updating == -1 && q.len(w.chunks_to_update) > 0
	{
		chunk_id := q.pop_front(&w.chunks_to_update)
		
		currently_updating = i32(chunk_id)
	}
}

draw :: proc() {
	rl.BeginDrawing()
	
	width := rl.GetRenderWidth()
	height := rl.GetRenderHeight()

	rl.ClearBackground(rl.WHITE)
	rl.BeginMode3D(camera)

	x := math.cos_f32(_time) * 5.0
	y := math.sin_f32(_time) * 5.0
	rl.DrawSphere({x, y, 0}, 0.5, rl.YELLOW)

	for	chunk_id in world.active_chunks 
	{
		chunk := &w.all_chunks[chunk_id]
		for &section in chunk.sections
		{
			position := section.position * w.SECTION_SIZE
			fpos := t.float3{f32(position.x), f32(position.y), f32(position.z)}

			if state.isWireframeRendering
			{
				rl.DrawCubeWires(fpos + 8, 16, 16, 16, rl.YELLOW)
			}

			if !section.hasModel
			{
				continue
			}

			m := rl.MatrixTranslate(f32(position.x), f32(position.y), f32(position.z))
			rl.DrawModel(section.model, fpos, 1, rl.WHITE)
		}
	}

	rl.EndMode3D()
	rl.DrawFPS(10, 10)
	rl.DrawTexture(texture, 50, 50, rl.WHITE)

	bar_width : f32 = 2
	green : t.color32 = t.color32{0, 255, 0, 255}
	yellow : t.color32 = t.color32{255, 255, 0, 255}
	red : t.color32 = t.color32{255, 0, 0, 255}
	
	blend :: proc(a, b: t.color32, f: f32) -> t.color32 {
		return t.color32 {
			u8(f32(a.r) * (1 - f) + f32(b.r) * f),
			u8(f32(a.g) * (1 - f) + f32(b.g) * f),
			u8(f32(a.b) * (1 - f) + f32(b.b) * f),
			u8(f32(a.a) * (1 - f) + f32(b.a) * f)
		}
	}
	
	// frametimes
	for i in 0..<len(frametimes) {
		index := (frametimes_pos + i32(i)) % len(frametimes)
		ft := frametimes[index]
		ticked := ticks[index]
		
		col : t.color32
		
		if (ft < 0.016)
		{
			col = green
		}
		else if (ft < 0.033)
		{
			t := (ft - 0.016) / (0.033 - 0.016)
			col = blend(green, yellow, t)
		}
		else if (ft < 0.066)
		{
			t := (ft - 0.033) / (0.066 - 0.033)
			col = blend(yellow, red, t)
		}

		rl.DrawRectangleV(t.float2{10 + bar_width * f32(i), 200}, t.float2{bar_width, ft*10000}, rl.Color(col))
		if ticked{
			rl.DrawRectangleV(t.float2{10 + bar_width * f32(i), 200}, t.float2{1, ft*10000}, rl.BLACK)
		}
	}
	
	
	y60fps : f32 = 200 + 0.01666 * 10000
	y30fps : f32 = 200 + 0.0333 * 10000
	y15fps : f32 = 200 + 0.0666 * 10000
	line_width := bar_width * len(frametimes)
	
	rl.DrawLineV(t.float2{10, y60fps}, t.float2{10 + line_width, y60fps}, rl.BLACK)
	rl.DrawLineV(t.float2{10, y30fps}, t.float2{10 + line_width, y30fps}, rl.BLACK)
	rl.DrawLineV(t.float2{10, y15fps}, t.float2{10 + line_width, y15fps}, rl.BLACK)
	
	// version
	rl.DrawText(version, 10, height - 26, 16, rl.BLACK)

	rl.EndDrawing()
}

update_input :: proc() {
	using input
	{
		if rl.IsKeyDown(.W){
			axis.x = 1
		}
		else if rl.IsKeyDown(.S){
			axis.x = -1
		}
		else {
			axis.x = 0
		}

		if rl.IsKeyDown(.A){
			axis.y = -1
		}
		else if rl.IsKeyDown(.D){
			axis.y = 1
		}
		else {
			axis.y = 0
		}

		jump = rl.IsKeyDown(.SPACE)
		run = rl.IsKeyDown(.LEFT_SHIFT)
	}

	if rl.IsKeyPressed(.F9) {
		state.isWireframeRendering = !state.isWireframeRendering
		log.log(.Info,"Clicked")
	}

	if rl.IsKeyPressed(.V) {
		state.doRaycast = !state.doRaycast
	}
}

@(export)
game_update :: proc() {
	update()
	draw()

	free_all(context.temp_allocator)
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(1280, 720, "Odin + Raylib + Hot Reload template!")
	rl.SetWindowPosition(200, 200)
	//rl.SetTargetFPS(500)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	mem.arena_init(&arena, data[:])

	context.allocator = mem.arena_allocator(&arena)
	log.log(.Info, "Hi")
	
	start()
}

@(export)
game_should_run :: proc() -> bool {
	when ODIN_OS != .JS 
	{
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() 
		{
			return false
		}
	}

	return true;
}

@(export)
game_shutdown :: proc() {
	for chunk_id in world.active_chunks {
		for section in w.all_chunks[chunk_id].sections {
			if section.hasModel {
				rl.UnloadModel(section.model)
			}
		}
	}
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}

/*
@(export)
game_memory :: proc() -> rawptr 
{
}

@(export)
game_memory_size :: proc() -> int 
{
	return 0;
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) 
{

}
*/
