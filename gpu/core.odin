package gpu

Descriptor_Base :: struct {
    label: string,
}

surface_get_format_priority :: proc(format: Texture_Format) -> int {
    #partial switch format {
    // Optimal sRGB formats for display (BGRA preferred over RGBA)
    case .Bgra8_Unorm_Srgb: return 6
    case .Rgba8_Unorm_Srgb: return 5 // Slightly lower priority than BGRA

    // Optimal linear formats (BGRA preferred over RGBA)
    case .Bgra8_Unorm: return 4
    case .Rgba8_Unorm: return 3 // Slightly lower priority than BGRA

    // Standard fallback formats
    case .Rgb10a2_Unorm, .Rgba16_Unorm: return 2

    // Less common but usable formats
    case .Rgba16_Float, .Rgba32_Float: return 1

    // Everything else is unsuitable for surface presentation
    case:
        return 0
    }
}

texture_dimension_to_view_dimension :: proc(
    dimension: Texture_Dimension,
) -> Texture_View_Dimension {
    switch dimension {
    case .D1:        return .D1
    case .D2:        return .D2
    case .D3:        return .D3
    case .Undefined: return .Undefined
    }
    unreachable()
}

// Texture format capability flags.
Format_Aspects :: bit_set[Format_Aspect; u64]
Format_Aspect :: enum {
    Color,
    Depth,
    Stencil,
    Plane0,
    Plane1,
    Plane2,
}

TEXTURE_ASPECTS_DEPTH_STENCIL :: Format_Aspects{ .Depth, .Stencil }

format_aspects_from :: proc(format: Texture_Format) -> Format_Aspects {
    #partial switch format {
    case .Stencil8: return { .Stencil }
    case .Depth16_Unorm,. Depth32_Float, .Depth24_Plus: return { .Depth }
    case .Depth32_Float_Stencil8, .Depth24_Plus_Stencil8: return TEXTURE_ASPECTS_DEPTH_STENCIL
    case .NV12, .P010: return { .Plane0, .Plane1 }
    }
    return { .Color }
}

Texture_View_Descriptor_Impl :: struct {
    label:     string,
    format:    Texture_Format,
    dimension: Texture_View_Dimension,
    usage:     Texture_Uses,
    range:     Image_Subresource_Range,
}

release :: proc {
    adapter_release,
    bind_group_release,
    bind_group_layout_release,
    buffer_release,
    command_buffer_release,
    command_encoder_release,
    compute_pass_release,
    device_release,
    instance_release,
    pipeline_layout_release,
    // query_set_release,
    queue_release,
    render_pass_release,
    render_pipeline_release,
    sampler_release,
    shader_module_release,
    surface_release,
    // surface_texture_release,
    texture_release,
    texture_view_release,
}
