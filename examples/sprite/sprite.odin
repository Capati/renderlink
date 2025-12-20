package sprite

// Core
import "core:log"
import "core:mem"

// Local packages
import rl "../../renderlink"

CLIENT_WIDTH       :: 640
CLIENT_HEIGHT      :: 480
EXAMPLE_TITLE      :: "Sprite"
VIDEO_MODE_DEFAULT :: rl.Video_Mode {
    width  = CLIENT_WIDTH,
    height = CLIENT_HEIGHT,
}

// Application struct holds the engine context and frame persistent data
Application :: struct {
    #subtype ctx: rl.Context,
    texture: rl.Texture,
}

init :: proc(self: ^Application) -> (ok: bool) {
    self.texture = rl.load_texture_from_memory(self, rl.TEXTURE_RENDERLINK)
    return true // init ok
}

draw :: proc(self: ^Application, dt: f32) -> (ok: bool) {
    rl.clear_color(self, { 240, 230, 214, 255 })
    rl.draw_sprite(self, self.texture, {0.0, 0.0}, rl.COLOR_WHITE, {5.0, 5.0})

    return true // keep ticking...
}

event :: proc(self: ^Application, event: rl.Event) -> (ok: bool) {
    return true // we keep running after this event
}

quit :: proc(self: ^Application) {
    rl.texture_destroy(self, self.texture)
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

    callbacks := rl.Application_Callbacks{
        init  = rl.App_Init_Callback(init),
        draw  = rl.App_Draw_Callback(draw),
        event = rl.App_Event_Callback(event),
        quit  = rl.App_Quit_Callback(quit),
    }

    rl.init(Application, VIDEO_MODE_DEFAULT, EXAMPLE_TITLE, callbacks)
}
