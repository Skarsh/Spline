package main


import "core:fmt"
import "core:math"
import "core:math/linalg/glsl"
import "core:testing"

EPSILON :: 1e-6

approx_equal :: proc(a, b: f32, epsilon: f32) -> bool {
	return math.abs(a - b) < epsilon
}

vec2_approx_equal :: proc(a, b: [2]f32, epsilon: f32) -> bool {
	return approx_equal(a.x, b.x, epsilon) && approx_equal(a.y, b.y, epsilon)
}

// Get spline for a given t [0.0 .. 1.0], Linear
get_spline_point_linear :: proc(
	start_pos: glsl.vec2,
	end_pos: glsl.vec2,
	t: f32,
) -> glsl.vec2 {
	point := glsl.vec2{}
	point = start_pos * (1.0 - t) + end_pos * t
	return point
}

// Get spline point for a given t [0.0 .. 1.0], B-spline
get_spline_point_basis :: proc(
	p1: glsl.vec2,
	p2: glsl.vec2,
	p3: glsl.vec2,
	p4: glsl.vec2,
	t: f32,
) -> glsl.vec2 {
	point := glsl.vec2{}

	temp := [4]glsl.vec2{}
	temp[0] = (-p1 + 3 * p2 - 3 * p3 + p4) / 6.0
	temp[1] = (3 * p1 - 6 * p2 + 3 * p3) / 6.0
	temp[2] = (-3 * p1 + 3 * p3) / 6.0
	temp[3] = (p1 + 4 * p2 + p3) / 6.0

	point = temp[3] + t * (temp[2] + t * (temp[1] + t * temp[0]))

	return point
}

// Get spline for a given t [0.0 .. 1.0], Catmull-Rom
get_spline_point_catmull_rom :: proc(
	p1: glsl.vec2,
	p2: glsl.vec2,
	p3: glsl.vec2,
	p4: glsl.vec2,
	t: f32,
) -> glsl.vec2 {
	point := glsl.vec2{}

	q0 := (-1 * t * t * t) + (2 * t * t) + (-1 * t)
	q1 := (3 * t * t * t) + (-5 * t * t) + 2
	q2 := (-3 * t * t * t) + (4 * t * t) + t
	q3 := t * t * t - t * t

	point = 0.5 * ((p1 * q0) + (p2 * q1) + (p3 * q2) + (p4 * q3))

	return point
}

// Get spline for a given t [0.0 .. 1.0], Quadratic Bezier
get_spline_point_bezier_quad :: proc(
	start_pos: glsl.vec2,
	control_pos: glsl.vec2,
	end_pos: glsl.vec2,
	t: f32,
) -> glsl.vec2 {
	point := glsl.vec2{}

	a := math.pow(1.0 - t, 2)
	b := 2.0 * (1.0 - t) * t
	c := math.pow(t, 2)

	point = a * start_pos + b * control_pos + c * end_pos

	return point
}

// Get spline for a given t [0.0 .. 1.0], Cubic Bezier
get_spline_point_bezier_cubic :: proc(
	start_pos: glsl.vec2,
	start_control_pos: glsl.vec2,
	end_control_pos: glsl.vec2,
	end_pos: glsl.vec2,
	t: f32,
) -> glsl.vec2 {
	point := glsl.vec2{}

	a := math.pow(1.0 - t, 3)
	b := 3.0 * math.pow(1.0 - t, 2) * t
	c := 3.0 * (1.0 - t) * math.pow(t, 2)
	d := math.pow(t, 3)

	point =
		a * start_pos +
		b * start_control_pos +
		c * end_control_pos +
		d * end_pos

	return point
}

@(test)
test_spline_point_linear_middle_point :: proc(t: ^testing.T) {
	start_pos := glsl.vec2{0.0, 0.0}
	end_pos := glsl.vec2{1.0, 1.0}

	middle_pos := get_spline_point_linear(start_pos, end_pos, 0.5)
	expected_middle_pos := glsl.vec2{0.5, 0.5}

	testing.expect(
		t,
		vec2_approx_equal(middle_pos.xy, expected_middle_pos.xy, EPSILON),
		fmt.tprintf(
			"Expected middle_pos to be (%f), got (%f)",
			expected_middle_pos,
			middle_pos,
		),
	)
}
