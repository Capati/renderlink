package renderlink

// Core
import la "core:math/linalg"

Camera_Matrix_Proc :: #type proc(camera: ^Camera, center: Vec2f) -> la.Matrix4f32

Camera_Uniform :: struct {
    view_position: [4]f32,
    view_proj:     la.Matrix4x4f32,
}

Camera :: struct {
    center:          Vec2f,
    zoom:            f32,
    aspect_ratio:    f32,
    use_matrix_proc: bool,
    matrix_proc:     Camera_Matrix_Proc,
}

camera_create :: proc(center := Vec2f{0, 0}, zoom: f32 = 30.0, aspect_ratio: f32 = 1.0) -> Camera {
    return {center = center, zoom = zoom, aspect_ratio = aspect_ratio}
}

camera_build_view_projection_matrix :: proc(self: ^Camera) -> la.Matrix4f32 {
    hx := self.zoom / 2.0
    hy := self.zoom / 2.0 / self.aspect_ratio

    range: f32 = 1000.0

    center := self.center

    ortho_camera := la.matrix_ortho3d_f32(
        left = center.x - hx,
        right = center.x + hx,
        bottom = center.y - hy,
        top = center.y + hy,
        near = -range,
        far = range,
    )

    if self.matrix_proc != nil && self.use_matrix_proc {
        return self.matrix_proc(self, center)
    }

    return ortho_camera
}

camera_set_zoom :: proc(self: ^Camera, zoom: f32) {
    self.zoom = zoom
}

camera_set_aspect_size :: proc(self: ^Camera, size: Vec2u) {
    self.aspect_ratio = f32(size.x) / f32(size.y)
}

camera_set_aspect_value :: proc(self: ^Camera, aspect: f32) {
    self.aspect_ratio = aspect
}

camera_set_aspect :: proc {
    camera_set_aspect_size,
    camera_set_aspect_value,
}

camera_get_zoom :: proc(self: ^Camera) -> f32 {
    return self.zoom
}

camera_get_aspect :: proc(self: ^Camera) -> f32 {
    return self.aspect_ratio
}

// Get the visible bounds by the camera.
camera_get_bounds :: proc(self: ^Camera) -> (min: Vec2f, max: Vec2f) {
    hx := self.zoom / 2.0
    hy := self.zoom / 2.0 / self.aspect_ratio
    min = self.center - {hx, hy}
    max = self.center + {hx, hy}
    return
}

// Get the total world width visible by the camera.
camera_get_world_width :: proc(self: ^Camera) -> f32 {
    return self.zoom
}

// Get the total world height visible by the camera.
camera_get_world_height :: proc(self: ^Camera) -> f32 {
    return self.zoom / self.aspect_ratio
}
