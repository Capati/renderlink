package renderlink

// Core
import sa "core:container/small_array"
import la "core:math/linalg"

Sprite_Vertex :: struct {
    position:   Vec3f,
    tex_coords: Vec2f,
    color:      Vec4f,
}

Mesh :: struct {
    origin:        Vec3f,
    vertices:      sa.Small_Array(4, Sprite_Vertex),
    indices:       sa.Small_Array(6, u32),
    z_index:       int,
    texture:       Texture,
    y_sort_offset: f32,
}

Render_Target :: distinct u32

Blend_Mode :: enum {
    None,
    Add,
    Alpha,
}

Mesh_Key :: struct {
    z_index:       int,
    blend_mode:    Blend_Mode,
    texture:       Texture,
    shader:        Shader,
    render_target: Render_Target,
}

Draw_Texture_Params :: struct {
    dest_size:     Maybe(Vec2f),
    source_rect:   Maybe(Recti),
    scroll_offset: Vec2f,
    rotation:      f32,
    flip_x:        bool,
    flip_y:        bool,
    pivot:         Maybe(Vec2f),
    blend_mode:    Blend_Mode,
    y_sort_offset: f32,
}

Raw_Draw_Params :: struct {
    source_rect: Maybe(Recti),
    dest_size:   Maybe(Vec2f),
    flip_x:      bool,
    flip_y:      bool,
    pivot:       Maybe(Vec2f),
    rotation:    f32,
}

clear_color :: #force_inline proc(ctx: ^Context, color: Color) {
    ctx.clear_color = {
        f64(color.r) / 255.0,
        f64(color.g) / 255.0,
        f64(color.b) / 255.0,
        f64(color.a) / 255.0,
    }
}

clear_background :: clear_color

draw_rect :: proc(ctx: ^Context, center, size: Vec2f, color: Color, z_index := 0) {
    draw_quad(ctx, center, size, color, ctx.default_texture, z_index)
}

Z_DIV: f32 : 1000.0

draw_rect_outline :: proc(
    ctx: ^Context,
    center, size: Vec2f,
    thickness: f32,
    color: Color,
    z_index := 0,
    loc := #caller_location,
) {
    w := size.x
    h := size.y

    hw := w / 2.0
    hh := h / 2.0

    // Draw as 4 filled rectangles (top, bottom, left, right)
    // Top
    draw_rect(ctx, {center.x, center.y - hh + thickness / 2}, {w, thickness}, color, z_index)
    // Bottom
    draw_rect(ctx, {center.x, center.y + hh - thickness / 2}, {w, thickness}, color, z_index)
    // Left
    draw_rect(
        ctx,
        {center.x - hw + thickness / 2, center.y},
        {thickness, h - thickness * 2},
        color,
        z_index,
    )
    // Right
    draw_rect(
        ctx,
        {center.x + hw - thickness / 2, center.y},
        {thickness, h - thickness * 2},
        color,
        z_index,
    )
}

create_line_segment :: proc(
    p0, p1: Vec2f,
    thickness: f32,
    z: f32,
    color: Vec4f,
) -> (
    vertices: sa.Small_Array(4, Sprite_Vertex),
    indices: sa.Small_Array(6, u32),
) {
    half_thickness := thickness / 4.0

    direction := la.normalize0(p1 - p0)
    if direction == {0, 0} {
        direction = {1, 0}
    }
    normal := Vec2f{-direction.y, direction.x}

    sa.push_back(
        &vertices,
        Sprite_Vertex {
            position = {(p0 - normal * half_thickness).x, (p0 - normal * half_thickness).y, z},
            tex_coords = {0, 0},
            color = color,
        },
    )
    sa.push_back(
        &vertices,
        Sprite_Vertex {
            position = {(p0 + normal * half_thickness).x, (p0 + normal * half_thickness).y, z},
            tex_coords = {0, 0},
            color = color,
        },
    )
    sa.push_back(
        &vertices,
        Sprite_Vertex {
            position = {(p1 - normal * half_thickness).x, (p1 - normal * half_thickness).y, z},
            tex_coords = {0, 0},
            color = color,
        },
    )
    sa.push_back(
        &vertices,
        Sprite_Vertex {
            position = {(p1 + normal * half_thickness).x, (p1 + normal * half_thickness).y, z},
            tex_coords = {0, 0},
            color = color,
        },
    )

    sa.push_back(&indices, 0)
    sa.push_back(&indices, 1)
    sa.push_back(&indices, 2)
    sa.push_back(&indices, 2)
    sa.push_back(&indices, 1)
    sa.push_back(&indices, 3)

    return
}

draw_quad :: proc(
    ctx: ^Context,
    center, size: Vec2f,
    color: Color,
    texture: Texture,
    z_index := 0,
    rotation: f32 = 0.0,
    scroll_offset: Vec2f = {},
) {
    params: Draw_Texture_Params
    params.dest_size = size
    params.rotation = rotation
    params.scroll_offset = scroll_offset
    draw_sprite_ex(ctx, texture, center, color, z_index, params)
}

draw_sprite :: proc(
    ctx: ^Context,
    texture: Texture,
    position: Vec2f,
    color: Color,
    size: Vec2f,
    tile_count: Vec2f = { 1.0, 1.0 },
    rotation: f32 = 0.0,
    #any_int z_index: int = 0,
) {
    vertices: sa.Small_Array(4, Sprite_Vertex)

    if rotation != 0.0 {
        // TODO
    } else {
        rect_vertices := simple_rect(
            {position.x, position.y, f32(z_index)},
            color,
            size,
            tile_count,
        )
        for v in rect_vertices {
            sa.push_back(&vertices, v)
        }
    }

    indices: sa.Small_Array(6, u32)
    for idx in QUAD_INDICES {
        sa.push_back(&indices, idx)
    }

    mesh := Mesh {
        origin        = {position.x, position.y, f32(z_index)},
        vertices      = vertices,
        indices       = indices,
        z_index       = z_index,
        texture       = texture,
        y_sort_offset = 0.0,
    }

    push_mesh(ctx, mesh, .None)
}

QUAD_INDICES: [6]u32 : {0, 2, 1, 0, 3, 2}

draw_sprite_ex :: proc(
    ctx: ^Context,
    texture: Texture,
    position: Vec2f,
    tint: Color,
    z_index: int,
    params: Draw_Texture_Params,
) {
    raw := Raw_Draw_Params {
        dest_size   = params.dest_size,
        source_rect = params.source_rect,
        rotation    = params.rotation,
        flip_x      = params.flip_x,
        flip_y      = params.flip_y,
        pivot       = params.pivot,
    }

    dimensions := texture_dimensions(ctx, texture)

    rect_vertices := rotated_rectangle(
        position = {position.x, position.y, f32(z_index)},
        params = raw,
        tex_width = f32(dimensions.width),
        tex_height = f32(dimensions.height),
        color = tint,
        scroll_offset = params.scroll_offset,
    )

    vertices: sa.Small_Array(4, Sprite_Vertex)
    for v in rect_vertices {
        sa.push_back(&vertices, v)
    }

    indices: sa.Small_Array(6, u32)
    for idx in QUAD_INDICES {
        sa.push_back(&indices, idx)
    }

    mesh := Mesh {
        origin        = {position.x, position.y, f32(z_index)},
        vertices      = vertices,
        indices       = indices,
        z_index       = z_index,
        texture       = texture,
        y_sort_offset = params.y_sort_offset,
    }

    push_mesh(ctx, mesh, params.blend_mode)
}
