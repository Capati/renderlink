package renderlink

// Core
// import "base:runtime"
import "core:mem"
import "core:log"
import la "core:math/linalg"
import intr "base:intrinsics"

// Local libs
import app "../application"
import "../gpu"

BUFFER_SIZE_DEFAULT :: 1024 * 1024

Context :: struct {
    // Base application subtype
    using base:       Application,

    // Initialization
    user_callbacks:   Application_Callbacks,

    // Pool of handles
    textures:         Pool(Texture_Impl),
    shaders:          Pool(Shader_Impl),

    // Graphics resources
    default_texture:  Texture,
    sprite_shader:    Shader,
    vertex_buffer:    Sized_Buffer,
    index_buffer:     Sized_Buffer,
    texture_layout: struct {
        layout:   gpu.Bind_Group_Layout,
        pipeline: gpu.Pipeline_Layout,
    },
    pipelines:        Pipeline_Map,

    // State
    y_sort_state:     Y_Sort_State,
    camera_uniform:   gpu.Buffer,
    camera:           Camera,
    clear_color:      gpu.Color,
    rpass: struct {
        colors:     [1]gpu.Render_Pass_Color_Attachment,
        descriptor: gpu.Render_Pass_Descriptor,
    },

    // Batching
    render_queues:    Render_Queues,
    staging_vertices: [dynamic]Sprite_Vertex,
    staging_indices:  [dynamic]u32,

    // Audio
    audio_ctx:        Audio_Context,

    // Internal
    arena:            mem.Dynamic_Arena, // frame allocator
}

// Opens a window and initializes the application context.
//
// Inputs:
// - `$T` - The application type to create. Must be a subtype of the base `Context`
// - `mode` - Video mode configuration (resolution, fullscreen, etc.)
// - `window_title` - Title displayed in the window's title bar
// - `callbacks` - Application lifecycle callbacks (init, step, event and quit)
// - `settings` - Optional window and GPU configuration settings
// - `allocator` - Memory allocator to use (defaults to context.allocator)
init :: proc(
    $T: typeid,
    mode: Video_Mode,
    window_title: string,
    callbacks: Application_Callbacks,
    settings := SETTINGS_DEFAULT,
    allocator := context.allocator,
    loc := #caller_location,
) where intr.type_is_subtype_of(T, Context) {
    ctx := cast(^Context)new(T, allocator)
    ensure(ctx != nil, "Failed to allocate the application context", loc)

    ctx.allocator = allocator
    ctx.user_callbacks = callbacks // store user callbacks

    // Window creation and callback management are handled by the application.
    // Here we register the engine callbacks, which will later invoke the
    // user-defined ones.
    engine_callbacks := Application_Callbacks {
        init  = App_Init_Callback(app_init_callback),
        draw  = App_Draw_Callback(app_draw_callback),
        event = App_Event_Callback(app_event_callback),
        quit  = App_Quit_Callback(app_quit_callback),
    }

    app.init(ctx, mode, window_title, engine_callbacks, allocator = allocator)
}

// Initializes the engine and, once setup is complete, calls the user's
// initialization callback.
app_init_callback :: proc(ctx: ^Context) -> (ok: bool) {
    context.allocator = ctx.allocator
    defer if !ok {
        free(ctx)
    }

    // Initialize pool of handles
    pool_init(&ctx.textures)
    pool_init(&ctx.shaders)

    defer if !ok {
        pool_destroy(&ctx.textures)
        pool_destroy(&ctx.shaders)
    }

    ctx.camera = camera_create()
    ctx.camera_uniform = gpu.device_create_buffer(ctx.base.device, {
        size = size_of(la.Matrix4f32),
        usage = {.Uniform, .Copy_Dst},
        mapped_at_creation = false,
    })
    defer if !ok { gpu.release(ctx.camera_uniform) }

    size := app.window_get_size(ctx.base.window)
    camera_set_aspect(&ctx.camera, size)

    // Create the default texture
    // This is the "1px" texture used for solid shapes
    ctx.default_texture = load_texture_from_memory(ctx,
        TEXTURE_DEFAULT,
        { label = "1px", filter_mode = .Nearest, address_mode = .Repeat },
    )
    defer if !ok { texture_destroy(ctx, ctx.default_texture) }

    // Default sprite shader
    ctx.sprite_shader = create_sprite_shader(ctx)
    defer if !ok { shader_destroy(ctx, ctx.sprite_shader) }

    // Create mesh vertex buffer
    ctx.vertex_buffer = create_buffer(
        ctx, "Mesh Vertex Buffer", BUFFER_SIZE_DEFAULT, {.Vertex, .Copy_Dst})
    defer if !ok { buffer_destroy(&ctx.vertex_buffer) }

    // Create mesh index buffer
    ctx.index_buffer = create_buffer(
        ctx, "Mesh Index Buffer", BUFFER_SIZE_DEFAULT, { .Index, .Copy_Dst })
    defer if !ok { buffer_destroy(&ctx.index_buffer) }

    // Create the default texture layout
    ctx.texture_layout.layout = gpu.device_create_bind_group_layout(ctx.base.device, {
        label = "Texture Bind Group Layout",
        entries = {
            {
                binding = 0,
                visibility = {.Vertex},
                type = gpu.Buffer_Binding_Layout {
                    type = .Uniform,
                    has_dynamic_offset = false,
                    min_binding_size = size_of(la.Matrix4f32),
                },
            },
            {
                binding = 1,
                visibility = {.Fragment},
                type = gpu.Texture_Binding_Layout {
                    sample_type = .Float,
                    view_dimension = .D2,
                    multisampled = false,
                },
            },
            {
                binding = 2,
                visibility = {.Fragment},
                type = gpu.Sampler_Binding_Layout {
                    type = .Filtering,
                },
            },
        },
    })
    ensure(ctx.texture_layout.layout != nil, "Failed to create Texture Bind Group Layout")
    defer if !ok { gpu.release(ctx.texture_layout.layout) }

    ctx.texture_layout.pipeline = gpu.device_create_pipeline_layout(ctx.base.device, {
        label = "Pipeline Layout",
        bind_group_layouts = { ctx.texture_layout.layout },
    })
    ensure(ctx.texture_layout.pipeline != nil, "Failed to create Texture Pipeline Layout")
    defer if !ok { gpu.release(ctx.texture_layout.pipeline) }

    // Initialize pipeline cache
    ctx.pipelines = make(Pipeline_Map)

    // Set default state
    ctx.rpass.descriptor = {
        label             = "Render Pass",
        color_attachments = ctx.rpass.colors[:],
    }

    // Batching allocator
    render_queues_init(&ctx.render_queues)

    ctx.staging_vertices.allocator = ctx.allocator
    ctx.staging_indices.allocator = ctx.allocator

    // Frame allocator
    mem.dynamic_arena_init(&ctx.arena)

    // Init audio context
    init_audio_context(&ctx.audio_ctx) or_return

    // Call user initialization
    if ctx.user_callbacks.init != nil && !ctx.user_callbacks.init(ctx) {
        log.errorf("Failed to initialize '%s'. Ensure init() returns true.",
           app.window_get_title(ctx.base.window))
        return
    }

    return true
}

app_draw_callback :: proc(ctx: ^Context, dt: f32) -> bool {
    // Begin frame

    size := app.window_get_size(ctx.base.window)
    camera_set_aspect(&ctx.camera, size)

    // User drawing

    if ctx.user_callbacks.draw != nil {
        if !ctx.user_callbacks.draw(ctx, dt) {
            return false
        }
    }

    // End frame

    frame := app.get_current_frame(ctx)
    if frame.skip { return true }
    defer app.release_current_frame(&frame)

    encoder := gpu.device_create_command_encoder(ctx.base.device)
    defer gpu.command_encoder_release(encoder)

    ctx.rpass.colors[0] = {
        view = frame.view,
        ops = {
            load = .Clear,
            store = .Store,
            clear_value = ctx.clear_color,
        },
    }

    rpass := gpu.command_encoder_begin_render_pass(encoder, ctx.rpass.descriptor)
    defer gpu.render_pass_release(rpass)

    // The allocator for this frame
    arena_alloc := mem.dynamic_arena_allocator(&ctx.arena)
    defer mem.dynamic_arena_reset(&ctx.arena)

    // Setup shared render state
    ortho_matrix := camera_build_view_projection_matrix(&ctx.camera)
    gpu.queue_write_buffer(
        ctx.base.queue,
        ctx.camera_uniform,
        0,
        to_bytes(ortho_matrix),
    )

    // Batch preparation
    batches := prepare_batches(ctx, arena_alloc)

    get_or_create_texture_bind_group :: proc(
        ctx: ^Context,
        texture_impl: ^Texture_Impl,
    ) -> gpu.Bind_Group {
        // Check if bind group already exists (cached in texture_impl)
        if texture_impl.bind_group != nil {
            return texture_impl.bind_group
        }

        // Create new bind group
        bind_group := gpu.device_create_bind_group(ctx.base.device, {
            label = "Texture Bind Group",
            layout = ctx.texture_layout.layout,
            entries = {
                {
                    binding = 0,
                    resource = gpu.Buffer_Binding {
                        buffer = ctx.camera_uniform,
                        size = gpu.buffer_get_size(ctx.camera_uniform),
                    },
                },
                {
                    binding = 1,
                    resource = texture_impl.view,
                },
                {
                    binding = 2,
                    resource = texture_impl.sampler,
                },
            },
        })
        ensure(bind_group != nil, "Failed to create texture bind group")

        // Cache it in the texture impl
        texture_impl.bind_group = bind_group

        return bind_group
    }

    current_pipeline: gpu.Render_Pipeline
    current_bind_group: gpu.Bind_Group

    for &batch in batches {
        // Bind pipeline (only if changed)
        pipeline := pipeline_from_key(ctx, {.Builtin, batch.key.shader, batch.key.blend_mode})
        if pipeline != current_pipeline {
            gpu.render_pass_set_pipeline(rpass, pipeline)
            current_pipeline = pipeline
        }

        // Bind texture bind group (only if changed)
        texture_impl := _texture_get_impl(ctx, batch.key.texture)

        // Create or get cached bind group for this texture
        bind_group := get_or_create_texture_bind_group(ctx, texture_impl)

        if bind_group != current_bind_group {
            gpu.render_pass_set_bind_group(rpass, 0, bind_group)
            current_bind_group = bind_group
        }

        // Bind vertex buffer with offset
        vertex_offset := u64(batch.vertex_offset * size_of(Sprite_Vertex))
        gpu.render_pass_set_vertex_buffer(
            rpass,
            0, // slot
            ctx.vertex_buffer.buffer,
            vertex_offset,
            gpu.WHOLE_SIZE,
        )

        // Bind index buffer with offset
        index_offset := u64(batch.index_offset * size_of(u32))
        gpu.render_pass_set_index_buffer(
            rpass,
            ctx.index_buffer.buffer,
            .Uint32,
            index_offset,
            gpu.WHOLE_SIZE,
        )

        // Draw batch
        gpu.render_pass_draw_indexed(
            rpass,
            indices = { 0, batch.index_count },
            base_vertex = 0,
        )
    }

    gpu.render_pass_end(rpass)

    cmdbuf := gpu.command_encoder_finish(encoder)
    defer gpu.command_buffer_release(cmdbuf)

    gpu.queue_submit(ctx.base.queue, { cmdbuf })
    gpu.surface_present(ctx.base.surface)

    render_queues_free(&ctx.render_queues)

    return true
}

app_event_callback :: proc(ctx: ^Context, event: Event) -> (ok: bool) {
    if ctx.user_callbacks.event != nil {
        if !ctx.user_callbacks.event(ctx, event) {
            return
        }
    }

    #partial switch &ev in event {
    case Quit_Event:
        log.info("Exiting...")
        return
    }

    return true
}

app_quit_callback :: proc(ctx: ^Context) {
    context.allocator = ctx.allocator
    if ctx.user_callbacks.quit != nil {
        ctx.user_callbacks.quit(ctx)
    }
    destroy(ctx)
}

destroy :: proc(ctx: ^Context) {
    context.allocator = ctx.allocator

    audio_context_destroy(&ctx.audio_ctx)

    mem.dynamic_arena_destroy(&ctx.arena)

    delete(ctx.staging_indices)
    delete(ctx.staging_vertices)

    render_queues_destroy(&ctx.render_queues)

    // Release graphic pipelines
    for _, v in ctx.pipelines {
        gpu.release(v)
    }
    delete(ctx.pipelines)
    gpu.release(ctx.texture_layout.pipeline)
    gpu.release(ctx.texture_layout.layout)

    // Release buffers
    buffer_destroy(&ctx.index_buffer)
    buffer_destroy(&ctx.vertex_buffer)

    // Destroy pool of texture handles
    texture_destroy(ctx, ctx.default_texture)
    if ctx.textures.num_objects > 0 {
        log.warnf("Leaked %d texture(s)", ctx.textures.num_objects)
    }
    pool_destroy(&ctx.textures)

    // Destroy pool of shader handles
    shader_destroy(ctx, ctx.sprite_shader)
    if ctx.shaders.num_objects > 0 {
        log.warnf("Leaked %d shader(s)", ctx.shaders.num_objects)
    }
    pool_destroy(&ctx.shaders)

    gpu.release(ctx.camera_uniform)

    app.destroy(ctx)
    free(ctx)
}
