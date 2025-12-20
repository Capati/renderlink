package application

// Core
import "base:runtime"
import "core:log"

// Libs
import "../libs/gpu"

GPU_Settings :: struct {
    power_preference:         gpu.Power_Preference,
    force_fallback_adapter:   bool,
    desired_surface_format:   gpu.Texture_Format,
    optional_features:        gpu.Features,
    required_features:        gpu.Features,
    required_limits:          gpu.Limits,
    desired_present_mode:     gpu.Present_Mode,
    remove_srgb_from_surface: bool,
}

GPU_SETTINGS_DEFAULT :: GPU_Settings {
    power_preference         = .High_Performance,
    required_limits          = gpu.LIMITS_DOWNLEVEL,
    desired_present_mode     = .Fifo,
    remove_srgb_from_surface = true,
}

GPU_Context :: struct {
    // === Initialization ===
    custom_context: runtime.Context,
    allocator:      runtime.Allocator,
    window:         Window,

    /* GPU Context */
    settings:       GPU_Settings,
    instance:       ^gpu.Instance,
    surface:        ^gpu.Surface,
    adapter:        ^gpu.Adapter,
    device:         ^gpu.Device,
    queue:          ^gpu.Queue,
    caps:           gpu.Surface_Capabilities,
    config:         gpu.Surface_Configuration,

    /* Settings */
    is_srgb:        bool,
    size:           Vec2u,
}

Frame_Texture :: struct {
    using _texture: gpu.Surface_Texture,
    skip:           bool,
    view:           gpu.Texture_View,
}

@(require_results)
get_current_frame :: proc(app: ^Application, loc := #caller_location) -> (frame: Frame_Texture) {
    if size := window_get_size(app.window); size != app.framebuffer_size {
        resize_surface(app.window, size, app)
    }

    frame._texture = gpu.surface_get_current_texture(app.surface)

    switch frame.status {
    case .Success_Optimal, .Success_Suboptimal:
    // All good, could handle suboptimal here

    case .Timeout, .Outdated, .Lost:
        // Skip this frame, and re-configure surface.
        release_current_frame(&frame)
        resize_surface(app.window, window_get_size(app.window), app)
        frame.skip = true
        return

    case .Out_Of_Memory, .Device_Lost, .Error:
        log.panicf("Failed to acquire surface texture: %v", frame.status, location = loc)
    }

    frame.view = gpu.texture_create_view(frame.texture, gpu.Texture_View_Descriptor {
        label = "Frame View",
    })

    assert(frame.texture != nil, "Invalid surface texture", loc)
    assert(frame.view != nil, "Invalid surface view", loc)

    return
}

release_current_frame :: proc(self: ^Frame_Texture) {
    gpu.texture_view_release(self.view)
    gpu.texture_release(self.texture)
}

resize_surface :: proc(window: Window, size: Vec2u, userdata: rawptr) {
    assert(userdata != nil)
    app := cast(^Application)userdata

    // Wait for the device to finish all operations
    when ODIN_OS != .JS {
        // gpu.device_poll(ctx.device, true)
    }

    app.config.width = u32(size.x)
    app.config.height = u32(size.y)

    // Reconfigure the surface
    // gpu.surface_unconfigure(app.surface)
    gpu.surface_configure(app.surface, app.device, app.config)

    app.framebuffer_size = size
}

Depth_Stencil_State_Descriptor :: struct {
    format:              gpu.Texture_Format,
    depth_write_enabled: bool,
}

DEFAULT_DEPTH_FORMAT :: gpu.Texture_Format.Depth24_Plus

create_depth_stencil_state :: proc(
    app: ^Application,
    desc: Depth_Stencil_State_Descriptor = {DEFAULT_DEPTH_FORMAT, true},
) -> gpu.Depth_Stencil_State {
    stencil_state_face_desc := gpu.Stencil_Face_State {
        compare       = .Always,
        fail_op       = .Keep,
        depth_fail_op = .Keep,
        pass_op       = .Keep,
    }

    format := desc.format if desc.format != .Undefined else DEFAULT_DEPTH_FORMAT

    return {
        format = format,
        depth_write_enabled = desc.depth_write_enabled,
        depth_compare = .Less_Equal,
        stencil = {
            front = stencil_state_face_desc,
            back = stencil_state_face_desc,
            read_mask = max(u32),
            write_mask = max(u32),
        },
    }
}

Depth_Stencil_Texture_Creation_Options :: struct {
    format:       gpu.Texture_Format,
    sample_count: u32,
}

Depth_Stencil_Texture :: struct {
    format:     gpu.Texture_Format,
    texture:    gpu.Texture,
    view:       gpu.Texture_View,
    descriptor: gpu.Render_Pass_Depth_Stencil_Attachment,
}

@(require_results)
create_depth_stencil_texture :: proc(
    device: gpu.Device,
    size: Vec2u,
    options: Depth_Stencil_Texture_Creation_Options = {},
) -> (
    ret: Depth_Stencil_Texture,
) {
    ret.format = options.format if options.format != .Undefined else DEFAULT_DEPTH_FORMAT

    sample_count := max(1, options.sample_count)

    width, height := expand_values(size)

    texture_descriptor := gpu.Texture_Descriptor {
        usage           = {.Render_Attachment, .Copy_Dst},
        format          = ret.format,
        dimension       = .D2,
        mip_level_count = 1,
        sample_count    = sample_count,
        size = {
            width                 = width,
            height                = height,
            depth_or_array_layers = 1,
        },
    }

    ret.texture = gpu.device_create_texture(device, texture_descriptor)

    texture_view_descriptor := gpu.Texture_View_Descriptor {
        format            = texture_descriptor.format,
        dimension         = .D2,
        base_mip_level    = 0,
        mip_level_count   = 1,
        base_array_layer  = 0,
        array_layer_count = 1,
        aspect            = .All,
    }

    ret.view = gpu.texture_create_view(ret.texture, texture_view_descriptor)

    ret.descriptor = {
        view = ret.view,
        depth_ops = {
            load = .Clear,
            store = .Store,
            clear_value = 1.0,
        },
    }

    return
}

release_depth_stencil_texture :: proc(self: Depth_Stencil_Texture) {
    gpu.release(self.texture)
    gpu.release(self.view)
}

get_backend_string :: proc(self: ^Application) -> string {
    switch gpu.device_get_backend(self.device) {
    case .Null:   return "Null"
    case .Vulkan: return "Vulkan"
    case .Metal:  return "Metal"
    case .Dx12:   return "Dx12"
    case .Dx11:   return "Dx11"
    case .Gl:     return "OpenGL"
    case .WebGPU: return "WebGPU"
    }
    unreachable()
}
