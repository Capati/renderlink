package bunnymark

// Core
import "core:log"
import "core:mem"
import "core:math/rand"
import la "core:math/linalg"

// Local packages
import rl "../../../renderlink"

CLIENT_WIDTH  :: 640
CLIENT_HEIGHT :: 480
EXAMPLE_TITLE :: "Bunnymark"

VIDEO_MODE_DEFAULT :: rl.Video_Mode {
    width  = CLIENT_WIDTH,
    height = CLIENT_HEIGHT,
}

WABBIT_DATA :: #load("wabbit_alpha.png")

MAX_BUNNIES :: 50000
GRAVITY : f32 = -1.0
MAX_VELOCITY : f32 = 32.0
BUNNIES_PER_TIME :: 500

Bunny :: struct {
    pos: rl.Vec2f,
    vel: rl.Vec2f,
    color: rl.Color,
}

Application :: struct {
    // Engine context
    #subtype ctx: rl.Context,

    // Frame data
    camera_zoom: f32,
    bunny_texture: rl.Texture,
    bunnies: [dynamic]Bunny,
}

init :: proc(self: ^Application) -> (ok: bool) {
    self.bunny_texture = rl.load_texture_from_memory(self, WABBIT_DATA)
    self.bunnies = make([dynamic]Bunny, 0, MAX_BUNNIES)

    // Start with some bunnies
    spawn_bunnies(self, BUNNIES_PER_TIME)

    self.camera_zoom = 20.0
    rl.camera_set_zoom(&self.ctx.camera, self.camera_zoom)

    return true // init ok
}

spawn_bunnies :: proc(self: ^Application, count: int) {
    for _ in 0..<count {
        if len(self.bunnies) >= int(MAX_BUNNIES) do break

        bunny := Bunny{
            pos = {0.0, 0.0}, // Center of screen
            vel = {
                rand.float32_range(-MAX_VELOCITY / 2, MAX_VELOCITY / 2),
                rand.float32_range(-MAX_VELOCITY / 2, MAX_VELOCITY / 2),
            },
            color = {
                u8(rand.int_max(190) + 50),
                u8(rand.int_max(160) + 80),
                u8(rand.int_max(140) + 100),
                255,
            },
        }
        append(&self.bunnies, bunny)
    }
}

update_bunnies :: proc(self: ^Application, dt: f32) {
    // Calculate world space bounds based on camera zoom
    half_height : f32 = self.camera_zoom / 2.0
    aspect_ratio := f32(CLIENT_WIDTH) / f32(CLIENT_HEIGHT)
    half_width := half_height * aspect_ratio

    for &bunny in self.bunnies {
        // Apply gravity
        bunny.vel.y += GRAVITY * dt

        // Clamp velocity
        speed := la.length(bunny.vel)
        if speed > MAX_VELOCITY {
            bunny.vel = la.normalize(bunny.vel) * MAX_VELOCITY
        }

        // Update position
        bunny.pos.x += bunny.vel.x * dt
        bunny.pos.y += bunny.vel.y * dt

        // Bounce off walls (left and right from center)
        if bunny.pos.x <= -half_width {
            bunny.pos.x = -half_width
            bunny.vel.x = -bunny.vel.x
        } else if bunny.pos.x >= half_width {
            bunny.pos.x = half_width
            bunny.vel.x = -bunny.vel.x
        }

        // Bounce off floor and ceiling (top and bottom from center)
        if bunny.pos.y <= -half_height {
            bunny.pos.y = -half_height
            bunny.vel.y = -bunny.vel.y * 0.85 // Some energy loss on bounce
        } else if bunny.pos.y >= half_height {
            bunny.pos.y = half_height
            bunny.vel.y = -bunny.vel.y
        }
    }
}

draw :: proc(self: ^Application, dt: f32) -> (ok: bool) {
    // Update bunnies
    update_bunnies(self, dt)

    if rl.key_is_down(self, .Space) {
        spawn_bunnies(self, BUNNIES_PER_TIME)
        log.infof("Total bunnies: %d", len(self.bunnies))
    }

    // Clear background
    rl.clear_color(self, {77, 102, 128, 255})

    // Draw all bunnies
    for &bunny in self.bunnies {
        rl.draw_sprite(
            self,
            self.bunny_texture,
            bunny.pos,
            bunny.color,
            { 1.0, 1.0 },
        )
    }

    return true // keep ticking...
}

event :: proc(self: ^Application, event: rl.Event) -> (ok: bool) {
    #partial switch e in event {
    case rl.Key_Pressed_Event:
        #partial switch e.key {
        case .Space:
            // spawn_bunnies(self, BUNNIES_PER_TIME)
        }
    }
    return true // we keep running after this event
}

quit :: proc(self: ^Application) {
    delete(self.bunnies)
    rl.texture_destroy(self, self.bunny_texture)
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
