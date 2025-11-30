package square

// Core
import "base:runtime"
import "core:log"
import "core:mem"

// Local packages
import "../../../gpu"
import "../common"
import app "../../../application"

CLIENT_WIDTH  :: 640
CLIENT_HEIGHT :: 480
EXAMPLE_TITLE :: "Square"
VIDEO_MODE_DEFAULT :: app.Video_Mode {
    width  = CLIENT_WIDTH,
    height = CLIENT_HEIGHT,
}

Application :: struct {
    using _app:       app.Application, // #subtype
    positions_buffer: gpu.Buffer,
    colors_buffer:    gpu.Buffer,
    render_pipeline:  gpu.Render_Pipeline,
    // Cache the render pass descriptor
    rpass: struct {
        colors:     [1]gpu.Render_Pass_Color_Attachment,
        descriptor: gpu.Render_Pass_Descriptor,
    },
}

@(rodata)
POSITIONS := [?]f32 {
    -0.5,  0.5, 0.0, // v0
     0.5,  0.5, 0.0, // v1
    -0.5, -0.5, 0.0, // v2
     0.5, -0.5, 0.0, // v3
}

@(rodata)
COLORS := [?]f32 {
    1.0, 0.0, 0.0, 1.0, // v0
    0.0, 1.0, 0.0, 1.0, // v1
    0.0, 0.0, 1.0, 1.0, // v2
    1.0, 1.0, 0.0, 1.0, // v3
}

init :: proc(self: ^Application) -> (ok: bool) {
    self.positions_buffer = gpu.device_create_buffer_with_data(
        self.device,
        {
            label = "Positions buffer",
            usage = {.Vertex, .Copy_Dst},
        },
        POSITIONS[:],
    )
    defer if !ok do gpu.buffer_release(self.positions_buffer)

    self.colors_buffer = gpu.device_create_buffer_with_data(
        self.device,
        {
            label = "Colors buffer",
            usage = {.Vertex, .Copy_Dst},
        },
        COLORS[:],
    )
    defer if !ok do gpu.buffer_release(self.colors_buffer)

    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    ta := context.temp_allocator

    // Load and create a shader module
    vertex_source :=
        common.load_shader_source(self.device, "03_square", .Vertex, ta) or_return
    vertex_shader := gpu.device_create_shader_module(
        self.device,
        {
            label = EXAMPLE_TITLE + " Vertex Shader",
            code = vertex_source,
            stage = .Vertex,
        },
    )
    defer gpu.shader_module_release(vertex_shader)

    fragment_source :=
        common.load_shader_source(self.device, "03_square", .Fragment, ta) or_return
    fragment_shader := gpu.device_create_shader_module(
        self.device,
        {
            label = EXAMPLE_TITLE + " Fragment Shader",
            code = fragment_source,
            stage = .Fragment,
        },
    )
    defer gpu.shader_module_release(fragment_shader)

    pipeline_descriptor := gpu.Render_Pipeline_Descriptor {
        label = EXAMPLE_TITLE + " Render Pipeline",
        vertex = {
            module = vertex_shader,
            entry_point = "vs_main",
            buffers = {
                {
                    array_stride = 3 * 4,
                    step_mode = .Vertex,
                    attributes = {{shader_location = 0, format = .Float32x3, offset = 0}},
                },
                {
                    array_stride = 4 * 4,
                    step_mode = .Vertex,
                    attributes = {{shader_location = 1, format = .Float32x4, offset = 0}},
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
        primitive = {
            topology = .Triangle_Strip,
            strip_index_format = .Uint32,
            front_face = .Ccw,
            cull_mode = .Front,
        },
        multisample = gpu.MULTISAMPLE_STATE_DEFAULT,
    }

    // Create the triangle pipeline
    self.render_pipeline =
        gpu.device_create_render_pipeline(self.device, pipeline_descriptor)

    self.rpass.colors[0] = {
        view = nil, // Assigned later
        ops  = { .Clear, .Store, { 0.0, 0.0, 0.0, 1.0 } },
    }

    self.rpass.descriptor = {
        label             = "Render pass descriptor",
        color_attachments = self.rpass.colors[:],
    }

    return true
}

step :: proc(self: ^Application, dt: f32) -> (ok: bool) {
    frame := app.get_current_frame(self)
    if frame.skip { return }
    defer app.release_current_frame(&frame)

    // Creates an empty command encoder
    encoder := gpu.device_create_command_encoder(self.device)
    defer gpu.command_encoder_release(encoder)

    // Begins recording of a render pass
    self.rpass.colors[0].view = frame.view
    rpass := gpu.command_encoder_begin_render_pass(encoder, self.rpass.descriptor)
    defer gpu.render_pass_release(rpass)

    // Sets the active render pipeline
    gpu.render_pass_set_pipeline(rpass, self.render_pipeline)

    // Bind vertex buffers (contain position & colors)
    gpu.render_pass_set_vertex_buffer(rpass, 0, self.positions_buffer)
    gpu.render_pass_set_vertex_buffer(rpass, 1, self.colors_buffer)

    // Draw quad
    gpu.render_pass_draw(rpass, {start = 0, end = 4})

    // Record the end of the render pass
    gpu.render_pass_end(rpass)

    cmdbuf := gpu.command_encoder_finish(encoder)
    defer gpu.command_buffer_release(cmdbuf)

    gpu.queue_submit(self.queue, {cmdbuf})
    gpu.surface_present(self.surface)

    return true
}

event :: proc(self: ^Application, event: app.Event) -> (ok: bool) {
    #partial switch &ev in event {
        case app.Quit_Event:
            log.info("Exiting...")
            return
    }
    return true
}

quit :: proc(self: ^Application) {
    gpu.buffer_release(self.colors_buffer)
    gpu.buffer_release(self.positions_buffer)
    gpu.render_pipeline_release(self.render_pipeline)

    app.destroy(self)
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
