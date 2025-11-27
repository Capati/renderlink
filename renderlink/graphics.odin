package renderlink

Sprite_Vertex :: struct {
    position:   Vec3f,
    tex_coords: Vec2f,
    color:      Vec4f,
}

Mesh :: struct {
    origin:        Vec3f,
    vertices:      [4]Sprite_Vertex,
    indices:       [6]u32,
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
    vertices: [4]Sprite_Vertex

    if rotation != 0.0 {
        // TODO
    } else {
        vertices = simple_rect({position.x, position.y, f32(z_index)}, color, size, tile_count)
    }

    mesh := Mesh {
        origin        = {position.x, position.y, f32(z_index)},
        vertices      = vertices,
        indices       = QUAD_INDICES,
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

    vertices := rotated_rectangle(
        position      = {position.x, position.y, f32(z_index)},
        params        = raw,
        tex_width     = f32(dimensions.width),
        tex_height    = f32(dimensions.height),
        color         = tint,
        scroll_offset = params.scroll_offset,
    )

    mesh := Mesh {
        vertices      = vertices,
        indices       = QUAD_INDICES,
        z_index       = z_index,
        texture       = texture,
        y_sort_offset = params.y_sort_offset,
    }

    push_mesh(ctx, mesh, params.blend_mode)
}
