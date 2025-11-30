package renderlink

// Core
import "core:math"
import la "core:math/linalg"
import sa "core:container/small_array"

Recti :: struct {
    offset: Vec2i,
    size:   Vec2i,
}

rotated_rectangle :: proc(
    position: Vec3f,
    params: Raw_Draw_Params,
    tex_width: f32,
    tex_height: f32,
    color: Color,
    scroll_offset: Vec2f,
) -> [4]Sprite_Vertex {
    x := position.x
    y := position.y

    dims: Recti
    if source_rect, has_source := params.source_rect.?; has_source {
        dims = {
            size   = source_rect.size,
            offset = {
                source_rect.offset.x,
                int(tex_height) - source_rect.offset.y - source_rect.size.y,
            },
        }
    } else {
        dims = {{}, {int(tex_width), int(tex_height)}}
    }

    sx := f32(dims.offset.x)
    sy := f32(dims.offset.y)
    sw := f32(dims.size.x)
    sh := f32(dims.size.y)

    w, h: f32
    if dest_size, has_dest := params.dest_size.?; has_dest {
        w = dest_size.x
        h = dest_size.y
    } else {
        w = 1.0
        h = 1.0
    }

    if params.flip_x {
        w = -w
    }
    if params.flip_y {
        h = -h
    }

    pivot: Vec2f
    if pivot_val, has_pivot := params.pivot.?; has_pivot {
        pivot = pivot_val
    } else {
        pivot = {x + w / 2.0, y + h / 2.0}
    }

    m := pivot - {w / 2.0, h / 2.0}

    r := params.rotation

    p := [4]Vec2f {
        Vec2f{x, y} - pivot,
        Vec2f{x + w, y} - pivot,
        Vec2f{x + w, y + h} - pivot,
        Vec2f{x, y + h} - pivot,
    }

    cos_r := math.cos(r)
    sin_r := math.sin(r)

    rotated_p := [4]Vec2f {
        Vec2f{p[0].x * cos_r - p[0].y * sin_r, p[0].x * sin_r + p[0].y * cos_r} + m,
        Vec2f{p[1].x * cos_r - p[1].y * sin_r, p[1].x * sin_r + p[1].y * cos_r} + m,
        Vec2f{p[2].x * cos_r - p[2].y * sin_r, p[2].x * sin_r + p[2].y * cos_r} + m,
        Vec2f{p[3].x * cos_r - p[3].y * sin_r, p[3].x * sin_r + p[3].y * cos_r} + m,
    }

    color_array := [4]f32 {
        f32(color.r) / 255.0,
        f32(color.g) / 255.0,
        f32(color.b) / 255.0,
        f32(color.a) / 255.0,
    }

    return {
        Sprite_Vertex {
            {rotated_p[0].x, rotated_p[0].y, position.z},
            Vec2f{sx / tex_width, sy / tex_height} + scroll_offset,
            color_array,
        },
        Sprite_Vertex {
            {rotated_p[1].x, rotated_p[1].y, position.z},
            Vec2f{(sx + sw) / tex_width, sy / tex_height} + scroll_offset,
            color_array,
        },
        Sprite_Vertex {
            {rotated_p[2].x, rotated_p[2].y, position.z},
            Vec2f{(sx + sw) / tex_width, (sy + sh) / tex_height} + scroll_offset,
            color_array,
        },
        Sprite_Vertex {
            {rotated_p[3].x, rotated_p[3].y, position.z},
            Vec2f{sx / tex_width, (sy + sh) / tex_height} + scroll_offset,
            color_array,
        },
    }
}

simple_rect :: proc(
    position: Vec3f,
    color: Color,
    dest_size: Vec2f,
    tile_count: Vec2f = { 1.0, 1.0 },
) -> [4]Sprite_Vertex {
    x := position.x
    y := position.y

    w := dest_size.x
    h := dest_size.y

    m := Vec2f{w / 2.0, h / 2.0}

    p := [4]Vec2f {
        Vec2f{x, y} - m,
        Vec2f{x + w, y} - m,
        Vec2f{x + w, y + h} - m,
        Vec2f{x, y + h} - m,
    }

    color_array := [4]f32 {
        f32(color.r) / 255.0,
        f32(color.g) / 255.0,
        f32(color.b) / 255.0,
        f32(color.a) / 255.0,
    }

    return {
        // Top-left
        Sprite_Vertex{{p[0].x, p[0].y, position.z}, {0.0, tile_count.y}, color_array},
        // Top-right
        Sprite_Vertex{{p[1].x, p[1].y, position.z}, {tile_count.x, tile_count.y}, color_array},
        // Bottom-right
        Sprite_Vertex{{p[2].x, p[2].y, position.z}, {tile_count.x, 0.0}, color_array},
        // Bottom-left
        Sprite_Vertex{{p[3].x, p[3].y, position.z}, {0.0, 0.0}, color_array},
    }
}

create_line_strip :: proc(
    points: []Vec2f,
    thickness: f32,
    vertices: ^sa.Small_Array(6 * 4, Vec2f),
    indices: ^sa.Small_Array(6 * 6, u32),
    loc := #caller_location,
) {
    assert(len(points) >= 2, "Not enough points to create a line strip!", loc)

    half_thickness := thickness / 4.0

    for i in 0..<(len(points) - 1) {
        p0 := points[i]
        p1 := points[i + 1]

        direction := la.normalize0(p1 - p0)
        if direction == {0, 0} {
            direction = {1, 0}
        }
        normal := Vec2f{-direction.y, direction.x}

        index_base := u32(vertices.len)

        sa.push_back(vertices, p0 - normal * half_thickness)
        sa.push_back(vertices, p0 + normal * half_thickness)
        sa.push_back(vertices, p1 - normal * half_thickness)
        sa.push_back(vertices, p1 + normal * half_thickness)

        sa.push_back(indices, index_base)
        sa.push_back(indices, index_base + 1)
        sa.push_back(indices, index_base + 2)

        sa.push_back(indices, index_base + 2)
        sa.push_back(indices, index_base + 1)
        sa.push_back(indices, index_base + 3)
    }
}
