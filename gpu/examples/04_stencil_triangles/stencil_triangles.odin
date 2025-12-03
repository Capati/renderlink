package stencil_triangles

// Core
import "base:runtime"
import "core:log"
import "core:mem"
import la "core:math/linalg"

// Local packages
import "../../../gpu"
import "../common"
import app "../../../application"

CLIENT_WIDTH  :: 640
CLIENT_HEIGHT :: 480
EXAMPLE_TITLE :: "Stencil Triangles"
VIDEO_MODE_DEFAULT :: app.Video_Mode {
    width  = CLIENT_WIDTH,
    height = CLIENT_HEIGHT,
}

STENCIL_FORMAT :: gpu.Texture_Format.Stencil8

Application :: struct {
    using _app:      app.Application, /* #subtype */

    outer_vertex_buffer: gpu.Buffer,
    mask_vertex_buffer:  gpu.Buffer,
    outer_pipeline:      gpu.Render_Pipeline,
    mask_pipeline:       gpu.Render_Pipeline,
    stencil_buffer:      gpu.Texture,
    depth_view:          gpu.Texture_View,
    depth_texture:       app.Depth_Stencil_Texture,
    rpass: struct {
        colors:     [1]gpu.Render_Pass_Color_Attachment,
        depth:      gpu.Render_Pass_Depth_Stencil_Attachment,
        descriptor: gpu.Render_Pass_Descriptor,
    },
}

Vertex :: struct {
    pos: la.Vector4f32,
}

vertex :: proc(x, y: f32) -> Vertex {
    return {pos = {x, y, 0.0, 1.0}}
}

init :: proc(self: ^Application) -> (ok: bool) {
    outer_vertices := []Vertex{vertex(-1.0, -1.0), vertex(1.0, -1.0), vertex(0.0, 1.0)}
    self.outer_vertex_buffer = gpu.device_create_buffer_with_data(
        self.device,
        {
            label = "Outer Vertex Buffer",
            usage = {.Vertex},
        },
        outer_vertices[:],
    )
    defer if !ok do gpu.buffer_release(self.outer_vertex_buffer)

    mask_vertices := []Vertex{vertex(-0.5, 0.0), vertex(0.0, -1.0), vertex(0.5, 0.0)}
    self.mask_vertex_buffer = gpu.device_create_buffer_with_data(
        self.device,
        {
            label = "Mask Vertex Buffer",
            usage = {.Vertex},
        },
        mask_vertices[:],
    )
    defer if !ok do gpu.buffer_release(self.mask_vertex_buffer)

    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    ta := context.temp_allocator

    // Load and create a shader module
    triangle_glsl_vertex :=
        common.load_shader_source(self.device, "04_stencil_triangles", .Vertex, ta) or_return
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
        common.load_shader_source(self.device, "04_stencil_triangles", .Fragment, ta) or_return
    fragment_shader := gpu.device_create_shader_module(
        self.device,
        {
            label = EXAMPLE_TITLE + " Fragment Shader",
            code = triangle_glsl_fragment,
            stage = .Fragment,
        },
    )
    defer gpu.shader_module_release(fragment_shader)

    vertex_buffers := [1]gpu.Vertex_Buffer_Layout {
        {
            array_stride = size_of(Vertex),
            step_mode    = .Vertex,
            attributes  = {{format = .Float32x4, offset = 0, shader_location = 0}},
        },
    }

    pipeline_descriptor := gpu.Render_Pipeline_Descriptor {
        label = EXAMPLE_TITLE + " Render Pipeline",
        vertex = {
            module = vertex_shader,
            entry_point = "vs_main",
            buffers = vertex_buffers[:],
        },
        fragment = &{
            module = fragment_shader,
            entry_point = "fs_main",
            targets = {
                {
                    format = self.config.format,
                    write_mask = gpu.COLOR_WRITES_NONE,
                },
            },
        },
        primitive = gpu.PRIMITIVE_STATE_DEFAULT,
        depth_stencil = &{
            format = STENCIL_FORMAT,
            depth_write_enabled = false,
            depth_compare = .Always,
            stencil = {
                front = {
                    compare = .Always,
                    fail_op = .Keep,
                    depth_fail_op = .Keep,
                    pass_op = .Replace,
                },
                back = gpu.STENCIL_FACE_STATE_IGNORE,
                read_mask = max(u32),
                write_mask = max(u32),
            },
        },
        multisample = gpu.MULTISAMPLE_STATE_DEFAULT,
    }

    pipeline_descriptor.label = "Mask Pipeline"

    self.mask_pipeline =
        gpu.device_create_render_pipeline(self.device, pipeline_descriptor)

    pipeline_descriptor.label = "Outer Pipeline"
    pipeline_descriptor.depth_stencil.stencil.front = {
        compare = .Greater,
        pass_op = .Keep,
    }
    pipeline_descriptor.fragment.targets[0].write_mask = gpu.COLOR_WRITES_ALL

    self.outer_pipeline =
        gpu.device_create_render_pipeline(self.device, pipeline_descriptor)

    self.rpass.colors[0] = {
        view = nil, // Assigned later
        ops  = { .Clear, .Store, { 0.1, 0.2, 0.3, 1.0 } },
    }

    self.rpass.descriptor = {
        label                    = "Render pass descriptor",
        color_attachments        = self.rpass.colors[:],
        depth_stencil_attachment = nil, // Assigned later
    }

    create_stencil_buffer(self, { self.config.width, self.config.height })

    return true
}

create_stencil_buffer :: proc(self: ^Application, size: app.Vec2u) {
    width, height := expand_values(size)

    self.stencil_buffer = gpu.device_create_texture(
        self.device,
        {
            label = "Stencil buffer",
            size = {
                width              = width,
                height             = height,
                depth_or_array_layers = 1,
            },
            mip_level_count = 1,
            sample_count    = 1,
            dimension       = .D2,
            format          = STENCIL_FORMAT,
            usage           = {.Render_Attachment},
        },
    )

    texture_view_descriptor := gpu.Texture_View_Descriptor {
        format            = STENCIL_FORMAT,
        dimension         = .D2,
        base_mip_level    = 0,
        mip_level_count   = 1,
        base_array_layer  = 0,
        array_layer_count = 1,
        aspect            = .All,
    }

    self.depth_view = gpu.texture_create_view(self.stencil_buffer, texture_view_descriptor)

    self.rpass.depth = {
        view = self.depth_view,
        depth_ops = {
            clear_value = 1.0,
        },
        stencil_ops = {
            load       = .Clear,
            store      = .Store,
            clear_value = 0.0,
        },
    }

    self.rpass.descriptor.depth_stencil_attachment = &self.rpass.depth
}

recreate_stencil_buffer :: proc(self: ^Application, size: app.Vec2u) {
    destroy_stencil_buffer(self)
    create_stencil_buffer(self, size)
}

destroy_stencil_buffer :: proc(self: ^Application) {
    gpu.release(self.stencil_buffer)
    gpu.release(self.depth_view)
}

step :: proc(self: ^Application, dt: f32) -> (ok: bool) {
    frame := app.get_current_frame(self)
    if frame.skip { return }
    defer app.release_current_frame(&frame)

    encoder := gpu.device_create_command_encoder(self.device)
    defer gpu.command_encoder_release(encoder)

    self.rpass.colors[0].view = frame.view
    render_pass := gpu.command_encoder_begin_render_pass(encoder, self.rpass.descriptor)
    defer gpu.render_pass_release(render_pass)

    gpu.render_pass_set_pipeline(render_pass, self.mask_pipeline)
    gpu.render_pass_set_stencil_reference(render_pass, 1)
    gpu.render_pass_set_vertex_buffer(render_pass, 0, self.mask_vertex_buffer)
    gpu.render_pass_draw(render_pass, {0, 3})

    gpu.render_pass_set_pipeline(render_pass, self.outer_pipeline)
    gpu.render_pass_set_stencil_reference(render_pass, 1)
    gpu.render_pass_set_vertex_buffer(render_pass, 0, self.outer_vertex_buffer)
    gpu.render_pass_draw(render_pass, {0, 3})

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

        case app.Resize_Event:
            recreate_stencil_buffer(self, ev.size)
    }

    return true
}

quit :: proc(self: ^Application) {
    destroy_stencil_buffer(self)

    gpu.release(self.outer_pipeline)
    gpu.release(self.mask_pipeline)
    gpu.release(self.mask_vertex_buffer)
    gpu.release(self.outer_vertex_buffer)

    app.destroy(self)
    free(self)
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

    callbacks := app.Application_Callbacks{
        init  = app.App_Init_Callback(init),
        draw  = app.App_Draw_Callback(step),
        event = app.App_Event_Callback(event),
        quit  = app.App_Quit_Callback(quit),
    }

    app.init(ctx, VIDEO_MODE_DEFAULT, EXAMPLE_TITLE, callbacks)
}
