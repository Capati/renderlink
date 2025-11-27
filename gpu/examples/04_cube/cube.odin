package cube

// Core
import "base:runtime"
import "core:log"
import "core:mem"
import la "core:math/linalg"

// Local packages
import "../../../gpu"
import "../common"
import app "../../../application"

CLIENT_WIDTH       :: 640
CLIENT_HEIGHT      :: 480
EXAMPLE_TITLE      :: "Cube"
VIDEO_MODE_DEFAULT :: app.Video_Mode {
    width  = CLIENT_WIDTH,
    height = CLIENT_HEIGHT,
}
DEPTH_FORMAT       :: gpu.Texture_Format.Depth24_Plus

Application :: struct {
    using _app:      app.Application, // subtype

    render_pipeline: gpu.Render_Pipeline,
    vertex_buffer:   gpu.Buffer,
    uniform_buffer:  gpu.Buffer,
    bind_group:      gpu.Bind_Group,
    depth_view:      gpu.Texture_View,

    // Cache the render pass descriptor
    rpass: struct {
        colors:                   [1]gpu.Render_Pass_Color_Attachment,
        depth_stencil_attachment: gpu.Render_Pass_Depth_Stencil_Attachment,
        descriptor:               gpu.Render_Pass_Descriptor,
    },
}

init :: proc(self: ^Application) -> (ok: bool) {
    self.vertex_buffer = gpu.device_create_buffer_with_data(
        self.device,
        {
            label = "Vertex buffer",
            usage = {.Vertex},
        },
        vertex_data[:],
    )
    defer if !ok do gpu.release(self.vertex_buffer)

    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    ta := context.temp_allocator

    // Load and create a shader module
    triangle_glsl_vertex :=
        common.load_shader_source(self.device, "04_cube", .Vertex, ta) or_return
    vertex_shader := gpu.device_create_shader_module(
        self.device,
        {
            label = EXAMPLE_TITLE + " Vertex Shader",
            code = triangle_glsl_vertex,
            stage = .Vertex,
        },
    )
    defer gpu.release(vertex_shader)

    triangle_glsl_fragment :=
        common.load_shader_source(self.device, "04_cube", .Fragment, ta) or_return
    fragment_shader := gpu.device_create_shader_module(
        self.device,
        {
            label = EXAMPLE_TITLE + " Fragment Shader",
            code = triangle_glsl_fragment,
            stage = .Fragment,
        },
    )
    defer gpu.release(fragment_shader)

    bind_group_layout := gpu.device_create_bind_group_layout(
        self.device,
        {
            label = EXAMPLE_TITLE + " Bind Group Layout",
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
            },
        },
    )
    defer gpu.release(bind_group_layout)

    pipeline_layout := gpu.device_create_pipeline_layout(
        self.device,
        {
            label = EXAMPLE_TITLE + " Pipeline Layout",
            bind_group_layouts = {bind_group_layout},
        },
    )
    defer gpu.release(pipeline_layout)

    pipeline_descriptor := gpu.Render_Pipeline_Descriptor {
        label = EXAMPLE_TITLE + " Render Pipeline",
        layout = pipeline_layout,
        vertex = {
            module = vertex_shader,
            entry_point = "vs_main",
            buffers = {
                {
                    array_stride = size_of(Vertex),
                    step_mode = .Vertex,
                    attributes = {
                        { format = .Float32x3, offset = 0, shader_location = 0 },
                        {
                            format = .Float32x3,
                            offset = u64(offset_of(Vertex, color)),
                            shader_location = 1,
                        },
                    },
                },
            },
        },
        fragment = &{
            module = fragment_shader,
            entry_point = "fs_main",
            targets = {
                {
                    format = self.config.format,
                    blend = &gpu.BLEND_STATE_NORMAL,
                    write_mask = gpu.COLOR_WRITES_ALL,
                },
            },
        },
        primitive = {topology = .Triangle_List, front_face = .Ccw, cull_mode = .Back},
        // Enable depth testing so that the fragment closest to the camera
        // is rendered in front.
        depth_stencil = &{
            format = DEPTH_FORMAT,
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
                read_mask = 0xFFFFFFFF,
                write_mask = 0xFFFFFFFF,
            },
        },
        multisample = {
            count = 1, // 1 means no sampling
            mask  = max(u32),
        },
    }

    // Create the triangle pipeline
    self.render_pipeline =
        gpu.device_create_render_pipeline(self.device, pipeline_descriptor)
    defer if !ok do gpu.release(self.render_pipeline)

    aspect := f32(self.config.width) / f32(self.config.height)
    mvp_mat := common.create_view_projection_matrix(aspect)

    self.uniform_buffer = gpu.device_create_buffer_with_data(
        self.device,
        {
            label = "Uniform buffer",
            usage = {.Uniform, .Copy_Dst},
        },
        gpu.to_bytes(mvp_mat),
    )
    defer if !ok do gpu.release(self.uniform_buffer)

    self.bind_group = gpu.device_create_bind_group(
        self.device,
        {
            layout = bind_group_layout,
            entries = {
                {
                    binding = 0,
                    resource = gpu.Buffer_Binding {
                        buffer = self.uniform_buffer,
                        size = gpu.buffer_get_size(self.uniform_buffer),
                    },
                },
            },
        },
    )
    defer if !ok do gpu.release(self.bind_group)

    self.rpass.colors[0] = {
        view = nil, // Assigned later
        ops = {
            load = .Clear,
            store = .Store,
            clear_value = app.COLOR_DARK_GRAY,
        },
    }

    self.rpass.descriptor = {
        label                    = "Render pass descriptor",
        color_attachments        = self.rpass.colors[:],
        depth_stencil_attachment = &self.rpass.depth_stencil_attachment,
    }

    create_depth_framebuffer(self)

    return true
}

create_depth_framebuffer :: proc(self: ^Application) {
    adapter_features := gpu.adapter_get_features(self.adapter)
    format_features :=
        gpu.texture_format_guaranteed_format_features(DEPTH_FORMAT, adapter_features)

    // Check if render attachment is supported
    assert(.Render_Attachment in format_features.allowed_usages,
           "Depth format does not support render attachment")

    size := app.window_get_size(self.window)

    texture_descriptor := gpu.Texture_Descriptor {
        size            = {size.x, size.y, 1},
        mip_level_count = 1,
        sample_count    = 1,
        dimension       = .D2,
        format          = DEPTH_FORMAT,
        usage           = format_features.allowed_usages,
    }

    texture := gpu.device_create_texture(self.device, texture_descriptor)
    defer gpu.release(texture)

    self.depth_view = gpu.texture_create_view(texture)

    // Setup depth stencil attachment
    self.rpass.depth_stencil_attachment = {
        view = self.depth_view,
        depth_ops = {
            load        = .Clear,
            store       = .Store,
            clear_value = 1.0,
        },
    }
}

step :: proc(self: ^Application, dt: f32) -> (ok: bool) {
    frame := app.get_current_frame(self)
    if frame.skip { return }
    defer app.release_current_frame(&frame)

    // Creates an empty Command_Encoder
    encoder := gpu.device_create_command_encoder(self.device)
    defer gpu.release(encoder)

    // Begins recording of a render pass
    self.rpass.colors[0].view = frame.view
    render_pass := gpu.command_encoder_begin_render_pass(encoder, self.rpass.descriptor)
    defer gpu.release(render_pass)

    // Sets the active render pipeline
    gpu.render_pass_set_pipeline(render_pass, self.render_pipeline)
    // Sets the active bind group
    gpu.render_pass_set_bind_group(render_pass, 0, self.bind_group)
    // Bind the vertex buffer (contain position & colors)
    gpu.render_pass_set_vertex_buffer(render_pass, 0, self.vertex_buffer)
    // Draws primitives in the range of vertices
    gpu.render_pass_draw(render_pass, {0, u32(len(vertex_data))})
    // Record the end of the render pass
    gpu.render_pass_end(render_pass)

    cmdbuf := gpu.command_encoder_finish(encoder)
    defer gpu.release(cmdbuf)

    gpu.queue_submit(self.queue, {cmdbuf})
    gpu.surface_present(self.surface)

    return true
}

event :: proc(self: ^Application, event: app.Event) -> (ok: bool) {
    #partial switch &ev in event {
        case app.Resize_Event:
            resize(self, ev.size)

        case app.Quit_Event:
            log.info("Exiting...")
            return
    }
    return true
}

quit :: proc(self: ^Application) {
    gpu.release(self.depth_view)
    gpu.release(self.bind_group)
    gpu.release(self.uniform_buffer)
    gpu.release(self.vertex_buffer)
    gpu.release(self.render_pipeline)
}

resize :: proc(self: ^Application, size: app.Vec2u) {
    gpu.texture_view_release(self.depth_view)
    create_depth_framebuffer(self)

    // Update uniform buffer with new aspect ratio
    aspect := f32(size.x) / f32(size.y)
    new_matrix := common.create_view_projection_matrix(aspect)
    gpu.queue_write_buffer(
        self.queue,
        self.uniform_buffer,
        0,
        gpu.to_bytes(new_matrix),
    )
}

main :: proc() {
    when ODIN_DEBUG {
        context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color})
        defer log.destroy_console_logger(context.logger)

        // TODO(Capati): The tracking allocator in WASM requires more flags to work?
        when ODIN_OS != .JS {
            track: mem.Tracking_Allocator
            mem.tracking_allocator_init(&track, context.allocator)
            context.allocator = mem.tracking_allocator(&track)

            defer {
                if len(track.allocation_map) > 0 {
                    log.warnf("=== %v allocations not freed: ===", len(track.allocation_map))
                    for _, entry in track.allocation_map {
                        log.debugf("- %v bytes @ %v", entry.size, entry.location)
                    }
                }
                mem.tracking_allocator_destroy(&track)
            }
        }
    }

    ctx := new(Application)
    defer free(ctx)

    callbacks := app.Application_Callbacks{
        init  = app.App_Init_Callback(init),
        draw  = app.App_Draw_Callback(step),
        event = app.App_Event_Callback(event),
        quit  = app.App_Quit_Callback(quit),
    }

    app.init(ctx, VIDEO_MODE_DEFAULT, EXAMPLE_TITLE, callbacks)
}
