package microui_example

// Core
import "core:log"
import "core:mem"

// Vendor
import mu "vendor:microui"

// Local packages
import "../../../gpu"
import app "../../../application"
import wgpu_mu "../../../utils/microui"

CLIENT_WIDTH  :: 800
CLIENT_HEIGHT :: 600
EXAMPLE_TITLE :: "MicroUI Example"

VIDEO_MODE_DEFAULT :: app.Video_Mode {
    width  = CLIENT_WIDTH,
    height = CLIENT_HEIGHT,
}

Application :: struct {
    using _app:      app.Application,
    mu_ctx:          ^mu.Context,
    log_buf:         [64000]u8,
    log_buf_len:     int,
    log_buf_updated: bool,
    bg:              mu.Color,
}

init :: proc(self: ^Application) -> (ok: bool) {
    mu_init_info := wgpu_mu.MICROUI_INIT_INFO_DEFAULT
    mu_init_info.device = self.device
    mu_init_info.format = self.config.format
    mu_init_info.width = self.config.width
    mu_init_info.height = self.config.height

    self.mu_ctx = new(mu.Context)
    mu.init(self.mu_ctx)
    self.mu_ctx.text_width = mu.default_atlas_text_width
    self.mu_ctx.text_height = mu.default_atlas_text_height

    // Initialize MicroUI renderer
    wgpu_mu.init(mu_init_info)

    // Set initial state
    self.bg = {56, 130, 210, 255}

    return true
}

step :: proc(self: ^Application, dt: f32) -> (ok: bool) {
    mu_update(self)

    frame := app.get_current_frame(self)
    if frame.skip { return }
    defer app.release_current_frame(&frame)

    encoder := gpu.device_create_command_encoder(self.device)
    defer gpu.release(encoder)

    color_attachment := gpu.Render_Pass_Color_Attachment {
        view = frame.view,
        ops  = {.Clear, .Store, get_color_from_mu_color(self.bg)},
    }

    rpass_desc := gpu.Render_Pass_Descriptor {
        label             = "MicroUI Render Pass",
        color_attachments = {color_attachment},
    }

    rpass := gpu.command_encoder_begin_render_pass(encoder, rpass_desc)
    defer gpu.release(rpass)

    wgpu_mu.begin(rpass)
    wgpu_mu.render(self.mu_ctx)

    gpu.render_pass_end(rpass)

    cmdbuf := gpu.command_encoder_finish(encoder)
    defer gpu.release(cmdbuf)

    gpu.queue_submit(self.queue, {cmdbuf})
    gpu.surface_present(self.surface)

    return true
}

event :: proc(self: ^Application, event: app.Event) -> (ok: bool) {
    app.mu_handle_events(self.mu_ctx, event)

    #partial switch &ev in event {
    case app.Quit_Event:
        log.info("Exiting...")
        return
    case app.Resize_Event:
        resize(self, ev.size)
    }

    return true
}

quit :: proc(self: ^Application) {
    wgpu_mu.destroy()
    free(self.mu_ctx)

    app.destroy(self)
    free(self)
}

resize :: proc(self: ^Application, size: app.Vec2u) {
    wgpu_mu.resize(i32(size.x), i32(size.y))
}

get_color_from_mu_color :: proc(color: mu.Color) -> gpu.Color {
    return {
        f64(color.r) / 255.0,
        f64(color.g) / 255.0,
        f64(color.b) / 255.0,
        1.0,
    }
}

mu_update :: proc(self: ^Application) {
    // UI definition
    mu.begin(self.mu_ctx)
    test_window(self, self.mu_ctx)
    log_window(self, self.mu_ctx)
    style_window(self, self.mu_ctx)
    mu.end(self.mu_ctx)
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

    callbacks := app.Application_Callbacks {
        init  = app.App_Init_Callback(init),
        draw  = app.App_Draw_Callback(step),
        event = app.App_Event_Callback(event),
        quit  = app.App_Quit_Callback(quit),
    }

    app.init(ctx, VIDEO_MODE_DEFAULT, EXAMPLE_TITLE, callbacks)
}
