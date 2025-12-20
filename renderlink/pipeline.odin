package renderlink

// Local libs
import "../libs/gpu"

Pipeline_Type :: enum u8 {
    Builtin,
    User,
}

Pipeline_Key :: struct {
    type:       Pipeline_Type,
    shader:     Shader,
    Blend_Mode: Blend_Mode,
}

Pipeline_Map :: map[Pipeline_Key]gpu.Render_Pipeline

pipeline_from_key :: proc(
    ctx: ^Context, key:
    Pipeline_Key,
    loc := #caller_location,
) -> gpu.Render_Pipeline {
    if key not_in ctx.pipelines {
        ctx.pipelines[key] = create_graphics_pipeline(
            ctx,
            ctx.base.config.format,
            .Undefined,
            ctx.sprite_shader,
            .Alpha,
        )
        ensure(ctx.pipelines[key] != nil, "Failed to create graphics pipeline", loc)
    }
    return ctx.pipelines[key]
}

create_graphics_pipeline :: proc(
    ctx: ^Context,
    color_format, depth_format: gpu.Texture_Format,
    shader: Shader,
    blend_mode: Blend_Mode,
    loc := #caller_location,
) -> gpu.Render_Pipeline {
    assert(shader_is_valid(shader), "Invalid shader handle", loc)
    shaders := pool_get(&ctx.shaders, to_handle(shader))

    assert(shaders.vs != nil, "Invalid vertex shader", loc)
    assert(shaders.fs != nil, "Invalid fragment shader", loc)

    // Setup blend state based on blend mode
    blend_state: gpu.Blend_State

    switch blend_mode {
    case .None, .Alpha:
        blend_state = {
            color = {
                src_factor = .Src_Alpha,
                dst_factor = .One_Minus_Src_Alpha,
                operation = .Add,
            },
            alpha = {
                src_factor = .One,
                dst_factor = .One_Minus_Src_Alpha,
                operation = .Add,
            },
        }

    case .Add:
        blend_state = {
            color = {
                src_factor = .One,
                dst_factor = .One,
                operation = .Add,
            },
            alpha = {
                src_factor = .One,
                dst_factor = .One,
                operation = .Add,
            },
        }
    }

    // Vertex attributes
    vertex_attributes := []gpu.Vertex_Attribute {
        {
            // position: POSITION (float3)
            format = .Float32x3,
            offset = 0,
            shader_location = 0,
        },
        {
            // tex_coords: TEXCOORD0 (float2)
            format = .Float32x2,
            offset = u64(offset_of(Sprite_Vertex, tex_coords)),
            shader_location = 1,
        },
        {
            // color: COLOR (float4)
            format = .Float32x4,
            offset = u64(offset_of(Sprite_Vertex, color)),
            shader_location = 2,
        },
    }

    // Vertex buffer layout
    vertex_buffer_layout := gpu.Vertex_Buffer_Layout {
        array_stride = size_of(Sprite_Vertex),
        step_mode = .Vertex,
        attributes = vertex_attributes[:],
    }

    // Vertex state
    vertex_state := gpu.Vertex_State {
        module = shaders.vs,
        entry_point = "vs_main",
        buffers = { vertex_buffer_layout },
    }

    // Color target state
    color_target := gpu.Color_Target_State {
        format = color_format,
        blend = &blend_state,
        write_mask = gpu.COLOR_WRITES_ALL,
    }

    // Fragment state
    fragment_state := gpu.Fragment_State {
        module = shaders.fs,
        entry_point = "fs_main",
        targets = { color_target },
    }

    // Primitive state
    primitive_state := gpu.Primitive_State {
        topology = .Triangle_List,
        front_face = .Ccw,
        cull_mode = .None,
    }

    // Depth stencil state (optional)
    depth_stencil_state: gpu.Depth_Stencil_State
    has_depth_stencil := depth_format != .Undefined

    depth_stencil_state_data: gpu.Depth_Stencil_State
    if has_depth_stencil {
        depth_stencil_state_data = {
            format = depth_format,
            depth_write_enabled = true,
            depth_compare = .Less,
            stencil = {
                front = {
                    compare = .Always,
                    fail_op = .Keep,
                    depth_fail_op = .Keep,
                    pass_op = .Keep,
                },
                back = {
                    compare = .Always,
                    fail_op = .Keep,
                    depth_fail_op = .Keep,
                    pass_op = .Keep,
                },
                read_mask = 0xFF,
                write_mask = 0xFF,
            },
        }
    }

    // Multisample state
    multisample_state := gpu.Multisample_State {
        count = 1,
        mask = 0xFFFFFFFF,
        alpha_to_coverage_enabled = false,
    }

    // Pipeline descriptor
    pipeline_desc := gpu.Render_Pipeline_Descriptor {
        label         = "Graphics Pipeline",
        layout        = ctx.texture_layout.pipeline,
        vertex        = vertex_state,
        primitive     = primitive_state,
        depth_stencil = has_depth_stencil ? &depth_stencil_state : nil,
        multisample   = multisample_state,
        fragment      = &fragment_state,
    }

    pipeline := gpu.device_create_render_pipeline(ctx.base.device, pipeline_desc)
    assert(pipeline != nil, "Failed to create graphics pipeline", loc)

    return pipeline
}
