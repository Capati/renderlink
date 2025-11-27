package clear_screen

// Core
import "core:log"
import "core:math"
import "core:mem"

// Local packages
import "../../../gpu"
import app "../../../application"

CLIENT_WIDTH       :: 640
CLIENT_HEIGHT      :: 480
EXAMPLE_TITLE      :: "Clear Screen"
VIDEO_MODE_DEFAULT :: app.Video_Mode {
    width  = CLIENT_WIDTH,
    height = CLIENT_HEIGHT,
}

Application :: struct {
    using _app:  app.Application, /* #subtype */
    clear_value: gpu.Color,
    rpass: struct {
        colors:     [1]gpu.Render_Pass_Color_Attachment,
        descriptor: gpu.Render_Pass_Descriptor,
    },
}

init :: proc(self: ^Application) -> (ok: bool) {
    self.clear_value = { 0.0, 0.0, 0.0, 1.0 }

    self.rpass.colors[0] = {
        view = nil, /* Assigned later */
        ops = {
            load = .Clear,
            store = .Store,
            clear_value = self.clear_value,
        },
    }

    self.rpass.descriptor = {
        label             = "Render pass descriptor",
        color_attachments = self.rpass.colors[:],
    }

    return true
}

update :: proc(self: ^Application, dt: f32) -> (ok: bool) {
    current_time := app.get_time(self)
    color := [4]f64 {
        math.sin(f64(current_time)) * 0.5 + 0.5,
        math.cos(f64(current_time)) * 0.5 + 0.5,
        0.0,
        1.0,
    }
    self.rpass.colors[0].ops.clear_value = color
    return true
}

step :: proc(self: ^Application, dt: f32) -> (ok: bool) {
    update(self, dt) or_return

    frame := app.get_current_frame(self)
    if frame.skip { return }
    defer app.release_current_frame(&frame)

    encoder := gpu.device_create_command_encoder(self.device)
    defer gpu.command_encoder_release(encoder)

    self.rpass.colors[0].view = frame.view
    rpass := gpu.command_encoder_begin_render_pass(encoder, self.rpass.descriptor)
    defer gpu.render_pass_release(rpass)

    gpu.render_pass_end(rpass)

    cmdbuf := gpu.command_encoder_finish(encoder)
    defer gpu.command_buffer_release(cmdbuf)

    gpu.queue_submit(self.queue, { cmdbuf })
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

quit :: proc(app: ^Application) {
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
