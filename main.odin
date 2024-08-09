package main

import "core:fmt"
import "core:math/linalg/glsl"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

import rl "vendor:raylib"

Point :: glsl.vec2

SplineType :: enum {
	BezierCubic,
	CatmullRom,
	BSpline,
}

// UI state
filename := "spline_config.txt"

filename_edit_mode := false
message: cstring
message_timer: f32 = 0

// File browser state
show_file_browser := false
current_directory: string
directory_files: []os.File_Info
selected_file_index := -1
scroll_offset := 0

control_points := []Point{{75, 450}, {200, 200}, {400, 400}, {600, 200}}
selected_point: int = -1
current_spline_type := SplineType.BezierCubic

// Vertex shader source code
vertex_shader_source := `
#version 330
in vec3 vertexPosition;
uniform mat4 mvp;

void main()
{
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

// Fragment shader source code
fragment_shader_source := `
#version 330
out vec4 finalColor;

void main()
{
    finalColor = vec4(0.0, 0.0, 1.0, 1.0);  // Blue color
}
`

save_configuration :: proc(filename: string) -> bool {
	file, err := os.open(filename, os.O_WRONLY | os.O_CREATE | os.O_TRUNC)
	if err != 0 {
		fmt.println("Error opening file for writing")
		return false
	}
	defer os.close(file)

	// Write spline type
	os.write_string(file, fmt.tprintf("%v\n", current_spline_type))

	// Write control points
	for point in control_points {
		os.write_string(file, fmt.tprintf("%f %f\n", point.x, point.y))
	}

	fmt.println("Configuration saved successfully")

	return true
}

load_configuration :: proc(filename: string) -> bool {
	data, success := os.read_entire_file(filename)
	if !success {
		fmt.println("Error reading file")
		return false
	}
	defer delete(data)

	lines := strings.split(string(data), "\n")
	defer delete(lines)

	if len(lines) < 5 { 	// Spline type + at least 4 control points
		fmt.println("Invalid configuration file")
		return false
	}

	// Read spline type
	spline_type_str := strings.trim_space(lines[0])
	switch spline_type_str {
	case "BezierCubic":
		current_spline_type = .BezierCubic
	case "CatmullRom":
		current_spline_type = .CatmullRom
	case "BSpline":
		current_spline_type = .BSpline
	case:
		fmt.println("Invalid spline type in configuration file")
		return false
	}

	// Read control points
	new_control_points := make([]Point, 4)
	for i in 0 ..< 4 {
		coords := strings.split(strings.trim_space(lines[i + 1]), " ")
		if len(coords) != 2 {
			fmt.println("Invalid control point in configuration file")
			return false
		}
		x, _ := strconv.parse_f32(coords[0])
		y, _ := strconv.parse_f32(coords[1])
		new_control_points[i] = Point{x, y}
	}

	control_points = new_control_points
	fmt.println("Configuration loaded successfully")
	return true
}


update_directory_files :: proc() {
	if directory_files != nil {
		delete(directory_files)
	}
	current_dir_handle, open_err := os.open(current_directory)

	if open_err != nil {
		rl.TraceLog(
			rl.TraceLogLevel.ERROR,
			"Error %s when opening directory %s",
			open_err,
			current_directory,
		)
	}

	read_dir_err: os.Error
	directory_files, read_dir_err = os.read_dir(current_dir_handle, -1)

	if read_dir_err != nil {
		rl.TraceLog(
			rl.TraceLogLevel.ERROR,
			"Error %s when reading directory %s",
			read_dir_err,
			current_directory,
		)
	}
}

draw_file_browser :: proc() {
	modal_rect := rl.Rectangle{100, 50, 600, 500}
	rl.DrawRectangleRec(modal_rect, rl.ColorAlpha(rl.LIGHTGRAY, 0.9))
	rl.DrawRectangleLinesEx(modal_rect, 2, rl.DARKGRAY)

	rl.DrawText("Select Configuration File", 120, 70, 20, rl.BLACK)

	// Draw current directory
	dir_text := fmt.tprintf("Current Directory: %s", current_directory)
	rl.DrawText(strings.clone_to_cstring(dir_text), 120, 100, 15, rl.DARKGRAY)

	// Draw file list
	list_rect := rl.Rectangle{120, 130, 560, 380}
	rl.BeginScissorMode(
		i32(list_rect.x),
		i32(list_rect.y),
		i32(list_rect.width),
		i32(list_rect.height),
	)

	for file, i in directory_files {
		y_pos := 130 + i32(i * 30) - i32(scroll_offset)
		if y_pos >= 130 && y_pos < 510 {
			if i == selected_file_index {
				rl.DrawRectangle(
					120,
					y_pos,
					560,
					30,
					rl.ColorAlpha(rl.BLUE, 0.3),
				)
			}

			// KEK!
			// TODO(Thomas): Use proper icons here, the default font map doesn't know what this is
			icon := file.is_dir ? "📁" : "📄"

			rl.DrawText(
				strings.clone_to_cstring(
					fmt.tprintf("%s %s", icon, file.name),
				),
				130,
				y_pos + 5,
				20,
				rl.BLACK,
			)
		}
	}

	rl.EndScissorMode()

	// Draw scrollbar
	if len(directory_files) * 30 > 380 {
		scrollbar_height := 380 * 380 / (len(directory_files) * 30)
		scrollbar_pos :=
			130 +
			(380 - scrollbar_height) *
				scroll_offset /
				((len(directory_files) * 30) - 380)
		rl.DrawRectangle(
			680,
			i32(scrollbar_pos),
			10,
			i32(scrollbar_height),
			rl.GRAY,
		)
	}

	// Draw buttons
	if rl.GuiButton(rl.Rectangle{120, 520, 100, 30}, "Load") {
		if selected_file_index >= 0 &&
		   selected_file_index < len(directory_files) {
			selected_file := directory_files[selected_file_index]
			if !selected_file.is_dir {
				full_path := filepath.join(
					{current_directory, selected_file.name},
				)
				if load_configuration(full_path) {
					message = "Configuration loaded successfully"
					show_file_browser = false
				} else {
					message = "Failed to load configuration"
				}
				message_timer = 3.0
			}
		}
	}

	if rl.GuiButton(rl.Rectangle{230, 520, 100, 30}, "Cancel") {
		show_file_browser = false
	}

}

main :: proc() {
	rl.InitWindow(800, 600, "Interactive Multi-Spline Renderer (Raylib)")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	fmt.println("Raylib initialized successfully")

	// Convert shader sources to C strings
	vertex_shader_source_cstr := strings.clone_to_cstring(vertex_shader_source)
	defer delete(vertex_shader_source_cstr)

	fragment_shader_source_cstr := strings.clone_to_cstring(
		fragment_shader_source,
	)
	defer delete(fragment_shader_source_cstr)

	// Load and compile custom shader
	shader := rl.LoadShaderFromMemory(
		vertex_shader_source_cstr,
		fragment_shader_source_cstr,
	)
	defer rl.UnloadShader(shader)

	fmt.println("Shader loaded successfully")

	// Initialize filename_buffer
	current_directory = os.get_current_directory()
	update_directory_files()

	for !rl.WindowShouldClose() {
		// Update
		mouse_position := rl.GetMousePosition()

		if !show_file_browser {
			if rl.IsMouseButtonPressed(.LEFT) {
				for point, i in control_points {
					if rl.CheckCollisionPointCircle(
						mouse_position,
						{point.x, point.y},
						10,
					) {
						selected_point = i
						break
					}
				}
			} else if rl.IsMouseButtonReleased(.LEFT) {
				selected_point = -1
			}

			if selected_point != -1 {
				control_points[selected_point] = Point {
					mouse_position.x,
					mouse_position.y,
				}
			}

			// Switch spline type
			if rl.IsKeyPressed(.ONE) {
				current_spline_type = .BezierCubic
			} else if rl.IsKeyPressed(.TWO) {
				current_spline_type = .CatmullRom
			} else if rl.IsKeyPressed(.THREE) {
				current_spline_type = .BSpline
			}
		} else {
			// File browser interaction
			if rl.IsMouseButtonPressed(.LEFT) {
				for file, i in directory_files {
					y_pos := 130 + i32(i * 30) - i32(scroll_offset)
					if y_pos >= 130 &&
					   y_pos < 510 &&
					   rl.CheckCollisionPointRec(
						   mouse_position,
						   rl.Rectangle{120, f32(y_pos), 560, 30},
					   ) {
						selected_file_index = i
						if file.is_dir && rl.IsMouseButtonPressed(.LEFT) {
							current_directory = filepath.join(
								{current_directory, file.name},
							)
							update_directory_files()
							selected_file_index = -1
							scroll_offset = 0
						}
						break
					}
				}
			}

			// Scrolling
			wheel_move := rl.GetMouseWheelMove()
			if wheel_move != 0 {
				scroll_offset -= int(wheel_move * 30)
				scroll_offset = clamp(
					scroll_offset,
					0,
					max(0, (len(directory_files) * 30) - 380),
				)
			}

		}

		// Generate curve points
		num_segments := 10_000
		curve_points := make([]rl.Vector2, num_segments + 1)
		defer delete(curve_points)
		for i := 0; i <= num_segments; i += 1 {
			t := f32(i) / f32(num_segments)
			p: Point
			switch current_spline_type {
			case .BezierCubic:
				p = get_spline_point_bezier_cubic(
					control_points[0],
					control_points[1],
					control_points[2],
					control_points[3],
					t,
				)
			case .CatmullRom:
				p = get_spline_point_catmull_rom(
					control_points[0],
					control_points[1],
					control_points[2],
					control_points[3],
					t,
				)
			case .BSpline:
				p = get_spline_point_basis(
					control_points[0],
					control_points[1],
					control_points[2],
					control_points[3],
					t,
				)
			}
			curve_points[i] = {p.x, p.y}
		}

		// Render
		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)

		// Use custom shader to draw the curve
		rl.BeginShaderMode(shader)
		rl.DrawLineStrip(
			raw_data(curve_points),
			i32(len(curve_points)),
			rl.BLUE,
		)
		rl.EndShaderMode()

		// Draw control points
		for point, i in control_points {
			rl.DrawCircleV({point.x, point.y}, 10, rl.RED)
			rl.DrawText(
				strings.clone_to_cstring(fmt.tprintf("P%d", i)),
				i32(point.x),
				i32(point.y),
				15,
				rl.BLACK,
			)
		}

		rl.DrawText(
			"Interactive Multi-Spline Renderer",
			10,
			10,
			20,
			rl.DARKGRAY,
		)
		rl.DrawText(
			"Click and drag control points to modify the curve",
			10,
			40,
			20,
			rl.DARKGRAY,
		)
		rl.DrawText(
			"Press 1 for Bezier, 2 for Catmull-Rom, 3 for B-Spline",
			10,
			70,
			20,
			rl.DARKGRAY,
		)

		spline_type_text := fmt.tprintf(
			"Current Spline: %v",
			current_spline_type,
		)

		rl.DrawText(
			strings.clone_to_cstring(spline_type_text),
			10,
			100,
			20,
			rl.DARKGRAY,
		)

		// UI elements for save/load
		filename_edit_mode := rl.GuiTextBox(
			rl.Rectangle{10, 520, 300, 30},
			strings.clone_to_cstring(filename),
			256,
			filename_edit_mode,
		)

		if rl.GuiButton(rl.Rectangle{320, 520, 100, 30}, "Save") {
			if save_configuration(filename) {
				message = "Configuration saved successfully"
			} else {
				message = "Failed to save configuration"
			}
			message_timer = 3.0 // Display message for 3 seconds
		}

		if rl.GuiButton(rl.Rectangle{430, 520, 100, 30}, "Load") {
			show_file_browser = true
		}

		// Display message
		if message_timer > 0 {
			rl.DrawText(message, 10, 560, 20, rl.RED)
			message_timer -= rl.GetFrameTime()
		}

		// Draw file browser if active
		if show_file_browser {
			draw_file_browser()
		}

		rl.EndDrawing()
	}

	fmt.println("Program ended normally")
}
