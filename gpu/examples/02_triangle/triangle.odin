package triangle

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
EXAMPLE_TITLE :: "Colored Triangle"
VIDEO_MODE_DEFAULT :: app.Video_Mode {
    width  = CLIENT_WIDTH,
    height = CLIENT_HEIGHT,
}

Application :: struct {
    using _app:      app.Application, /* #subtype */
    render_pipeline: gpu.Render_Pipeline,
    vertex_buffer:   gpu.Buffer,
    rpass: struct {
        colors:     [1]gpu.Render_Pass_Color_Attachment,
        descriptor: gpu.Render_Pass_Descriptor,
    },
}

@(rodata)
VERTICES := [?]f32 {
    // pos            color
     0.0 , 0.5, 0.0,  1,0,0,1,
     0.5, -0.5, 0.0,  0,1,0,1,
    -0.5, -0.5, 0.0,  0,0,1,1,
}

init :: proc(self: ^Application) -> (ok: bool) {
    self.vertex_buffer = gpu.device_create_buffer_with_data(
        self.device,
        {
            label = "Vertex buffer",
            usage = {.Vertex, .Copy_Dst},
        },
        VERTICES[:],
    )
    defer if !ok do gpu.buffer_release(self.vertex_buffer)

    backend_formats := gpu.instance_get_backend_shader_formats(self.instance)

    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    ta := context.temp_allocator

    // Load and create a shader module
    triangle_glsl_vertex :=
        common.load_shader_source(self.device, "02_triangle", .Vertex, ta) or_return
    vertex_shader := gpu.device_create_shader_module(
        self.device,
        {
            label = EXAMPLE_TITLE + " Vertex Shader",
            code = triangle_glsl_vertex,
            stage = .Vertex,
        },
    )
    defer gpu.shader_module_release(vertex_shader)

    triangle_glsl_fragment :=
        common.load_shader_source(self.device, "02_triangle", .Fragment, ta) or_return
    fragment_shader := gpu.device_create_shader_module(
        self.device,
        {
            label = EXAMPLE_TITLE + " Fragment Shader",
            code = triangle_glsl_fragment,
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
                    array_stride = 7 * size_of(f32), // 3 floats for pos + 4 floats for color
                    step_mode = .Vertex,
                    attributes = {
                        { format = .Float32x3, offset = 0, shader_location = 0 },
                        { format = .Float32x4, offset = 3 * size_of(f32), shader_location = 1 },
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
        primitive = {
            topology = .Triangle_List,
            front_face = .Ccw,
            cull_mode = .None,
        },
        multisample = {
            count = 1, // 1 means no sampling
            mask  = max(u32),
        },
    }

    // // Create the triangle pipeline
    self.render_pipeline =
        gpu.device_create_render_pipeline(self.device, pipeline_descriptor)

    self.rpass.colors[0] = {
        view = nil, /* Assigned later */
        ops  = {.Clear, .Store, { 0, 0, 0, 1 }},
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

    // Creates an empty Command_Encoder
    encoder := gpu.device_create_command_encoder(self.device)
    defer gpu.command_encoder_release(encoder)

    // Begins recording of a render pass
    self.rpass.colors[0].view = frame.view
    render_pass := gpu.command_encoder_begin_render_pass(encoder, self.rpass.descriptor)
    defer gpu.render_pass_release(render_pass)

    // Sets the active render pipeline
    gpu.render_pass_set_pipeline(render_pass, self.render_pipeline)
    // Bind vertex the buffer (contain position & colors)
    gpu.render_pass_set_vertex_buffer(render_pass, 0, self.vertex_buffer)
    // Draws primitives in the range of vertices
    gpu.render_pass_draw(render_pass, {start = 0, end = 3})
    // Record the end of the render pass
    gpu.render_pass_end(render_pass)

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
    gpu.buffer_release(self.vertex_buffer)
    gpu.render_pipeline_release(self.render_pipeline)
}

main :: proc() {
    when ODIN_DEBUG {
        context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color})
        defer log.destroy_console_logger(context.logger)

        // TODO(Capati): WASM requires additional flags for the tracking allocator?
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
