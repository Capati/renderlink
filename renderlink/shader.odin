package renderlink

// Local libs
import "../gpu"

Shader :: distinct Handle

@(private)
Shader_Impl :: struct {
    label:  String_Buffer_Small,
    device: gpu.Device,
    vs:     gpu.Shader_Module,
    fs:     gpu.Shader_Module,
}

create_shader :: proc(ctx: ^Context, code: []u8) {
}

create_sprite_shader :: proc(ctx: ^Context, loc := #caller_location) -> (shader: Shader) {
    vs_source: []u8
    fs_source: []u8

    when ODIN_OS == .JS {
        vs_source = #load("./assets/shaders/WGSL/sprite.vert.wgsl")
        fs_source = #load("./assets/shaders/WGSL/sprite.frag.wgsl")
    } else {
        #partial switch gpu.device_get_backend(ctx.base.device) {
        case .Vulkan:
            vs_source = #load("./assets/shaders/SPIRV/sprite.vert.spv")
            fs_source = #load("./assets/shaders/SPIRV/sprite.frag.spv")

        case .Gl:
            when ODIN_OS == .Windows || ODIN_OS == .Linux {
                vs_source = #load("./assets/shaders/GLSL/sprite.vert")
                fs_source = #load("./assets/shaders/GLSL/sprite.frag")
            } else {
                panic("OpenGL backend not supported on this platform")
            }

        case .Metal:
            when ODIN_OS == .Darwin {
                vs_source = #load("./assets/shaders/MSL/sprite.vert.metal")
                fs_source = #load("./assets/shaders/MSL/sprite.frag.metal")
            } else {
                panic("Metal backend only supported on macOS")
            }

        case:
            panic("Unsupported backend", loc)
        }
    }

    vertex_shader := gpu.device_create_shader_module(
        ctx.base.device,
        {
            label = "Sprite Vertex Shader",
            code = vs_source,
            stage = .Vertex,
        },
    )

    fragment_shader := gpu.device_create_shader_module(
        ctx.base.device,
        {
            label = "Sprite Fragment Shader",
            code = fs_source,
            stage = .Fragment,
        },
    )

    impl := Shader_Impl {
        device = ctx.base.device,
        vs     = vertex_shader,
        fs     = fragment_shader,
    }

    shader_handle := pool_create(&ctx.shaders, impl)
    return Shader(from_handle(shader_handle))
}

shader_destroy :: proc(ctx: ^Context, shader: Shader) {
    handle := to_handle(shader)
    assert(handle_is_valid(handle), "Invalid shader handle")
    impl := pool_get(&ctx.shaders, handle)
    gpu.release(impl.vs)
    gpu.release(impl.fs)
    pool_remove(&ctx.shaders, handle)
}

shader_is_valid :: #force_inline proc(shader: Shader) -> bool {
    return handle_is_valid(to_handle(shader))
}
