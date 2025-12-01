package renderlink

// Core
import "core:math"

// Vec2f constants
VEC2F_ZERO     :: Vec2f{0, 0}
VEC2F_ONE      :: Vec2f{1, 1}
VEC2F_RIGHT    :: Vec2f{1, 0}
VEC2F_LEFT     :: Vec2f{-1, 0}
VEC2F_UP       :: Vec2f{0, 1}
VEC2F_DOWN     :: Vec2f{0, -1}

// Vec2i constants
VEC2I_ZERO     :: Vec2i{0, 0}
VEC2I_ONE      :: Vec2i{1, 1}
VEC2I_RIGHT    :: Vec2i{1, 0}
VEC2I_LEFT     :: Vec2i{-1, 0}
VEC2I_UP       :: Vec2i{0, 1}
VEC2I_DOWN     :: Vec2i{0, -1}

// Vec3f constants
VEC3F_ZERO     :: Vec3f{0, 0, 0}
VEC3F_ONE      :: Vec3f{1, 1, 1}
VEC3F_RIGHT    :: Vec3f{1, 0, 0}
VEC3F_LEFT     :: Vec3f{-1, 0, 0}
VEC3F_UP       :: Vec3f{0, 1, 0}
VEC3F_DOWN     :: Vec3f{0, -1, 0}
VEC3F_FORWARD  :: Vec3f{0, 0, 1}
VEC3F_BACK     :: Vec3f{0, 0, -1}

// Vec3i constants
VEC3I_ZERO     :: Vec3i{0, 0, 0}
VEC3I_ONE      :: Vec3i{1, 1, 1}
VEC3I_RIGHT    :: Vec3i{1, 0, 0}
VEC3I_LEFT     :: Vec3i{-1, 0, 0}
VEC3I_UP       :: Vec3i{0, 1, 0}
VEC3I_DOWN     :: Vec3i{0, -1, 0}
VEC3I_FORWARD  :: Vec3i{0, 0, 1}
VEC3I_BACK     :: Vec3i{0, 0, -1}

positive_remainder :: #force_inline proc "contextless" (a, b: f32) -> f32 {
    assert_contextless(b > 0.0, "Cannot calculate remainder with non-positive divisor")
    val := a - f32(int(a / b)) * b
    return val >= 0.0 ? val : val + b
}

Angle :: f32 // angle in radians

angle_as_degrees :: #force_inline proc "contextless" (self: Angle) -> f32 {
    return self * (180.0 / math.PI)
}

angle_from_degrees :: #force_inline proc "contextless" (angle: f32) -> Angle {
    return Angle(angle * (math.PI / 180.0))
}

angle_degrees :: angle_from_degrees

angle_wrap_signed :: #force_inline proc "contextless" (self: Angle) -> Angle {
    return positive_remainder(self + math.PI, math.TAU) - math.PI
}
