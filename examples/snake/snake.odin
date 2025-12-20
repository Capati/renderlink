package snake

// Core
import "core:log"
import "core:math"
import "core:mem"
import "core:math/rand"
import "core:time"
import sa "core:container/small_array"

// Local packages
import rl "../../renderlink"

EXAMPLE_TITLE      :: "Snake"

GRID_WIDTH       :: 30
GRID_COUNT       :: 25
CELL_SIZE        :: GRID_WIDTH / GRID_WIDTH // 1.0 world units per cell
MAX_SNAKE_LENGTH :: GRID_WIDTH * GRID_WIDTH
TICK_RATE        :: 0.1

VIDEO_MODE_DEFAULT :: rl.Video_Mode {
    width  = GRID_WIDTH * GRID_COUNT, // 750px
    height = GRID_WIDTH * GRID_COUNT, // 750px
}

Snake :: struct {
    pos:       rl.Vec2i,
    direction: rl.Vec2i,
    next_direction: rl.Vec2i,
    body:      [MAX_SNAKE_LENGTH]rl.Vec2i,
    length: int,
}

Application :: struct {
    // Engine context
    #subtype ctx:       rl.Context,

    // Game data
    snake:              Snake,
    food_pos:           rl.Vec2i,
    tick_rate:          f32,
    tick_timer:         f32,
    food_texture:       rl.Texture,
    body_texture:       rl.Texture,
    background_texture: rl.Texture,
    eat_sound:          rl.Sound,
    crash_sound:        rl.Sound,
    bounds: struct {
        min, max:                 rl.Vec2f,
        word_width, world_height: f32,
    },
    is_game_over:       bool,
}

init :: proc(self: ^Application) -> (ok: bool) {
    rl.camera_set_zoom(&self.ctx.camera, 29.0)

    // Initial state
    restart(self)

    texture_info := rl.DEFAULT_TEXTURE_INFO // defaults to nearest filer

    // Load textures
    self.food_texture = rl.load_texture(self, "assets/snake/food.png") or_return
    defer if !ok { rl.texture_destroy(self, self.food_texture) }

    self.body_texture = rl.load_texture(self, "assets/snake/body.png") or_return
    defer if !ok { rl.texture_destroy(self, self.body_texture) }

    texture_info.address_mode = .Repeat
    self.background_texture = rl.load_texture(self,
        "assets/snake/background.png", texture_info) or_return
    defer if !ok { rl.texture_destroy(self, self.background_texture) }

    // Load sounds
    self.eat_sound = rl.sound_load(self, "assets/snake/eat.wav") or_return
    defer if !ok { rl.sound_destroy(self, self.eat_sound) }

    self.crash_sound = rl.sound_load(self, "assets/snake/crash.wav") or_return
    defer if !ok { rl.sound_destroy(self, self.crash_sound) }

    return true // init ok
}

restart :: proc(self: ^Application) {
    start_head_pos := rl.Vec2i{}
    self.snake.body[0] = start_head_pos
    self.snake.body[1] = start_head_pos + { 0, 1 }
    self.snake.body[2] = start_head_pos + { 0, 2 }
    self.snake.length = 3
    self.snake.direction = rl.VEC2I_DOWN // start moving down
    self.snake.next_direction = self.snake.direction
    self.is_game_over = false
    self.tick_rate = TICK_RATE
    place_food(self)
}

place_food :: proc(self: ^Application) {
    // Get camera bounds
    min_bounds, max_bounds := rl.camera_get_bounds(&self.ctx.camera)

    occupied: [GRID_WIDTH][GRID_WIDTH]bool
    for i in 0 ..< self.snake.length {
        pos := self.snake.body[i]
        // Convert from centered coordinates to array indices
        array_x := pos.x + GRID_WIDTH / 2
        array_y := pos.y + GRID_WIDTH / 2

        // Bounds check for array access
        if array_x >= 0 && array_x < GRID_WIDTH && array_y >= 0 && array_y < GRID_WIDTH {
            occupied[array_x][array_y] = true
        }
    }

    // Maximum possible free cells is GRID_WIDTH * GRID_WIDTH
    free_cells: sa.Small_Array(GRID_WIDTH * GRID_WIDTH, rl.Vec2i)

    for x in 0 ..< GRID_WIDTH {
        for y in 0 ..< GRID_WIDTH {
            if !occupied[x][y] {
                world_x := x - GRID_WIDTH / 2
                world_y := y - GRID_WIDTH / 2

                // Only add cells that are within camera bounds
                if f32(world_x) >= min_bounds.x && f32(world_x) <= max_bounds.x &&
                   f32(world_y) >= min_bounds.y && f32(world_y) <= max_bounds.y {
                    sa.push_back(&free_cells, rl.Vec2i{world_x, world_y})
                }
            }
        }
    }

    if sa.len(free_cells) > 0 {
        rand.reset(u64(time.time_to_unix(time.now())))
        random_pos := rand.int63_max(i64(sa.len(free_cells) - 1))
        self.food_pos = sa.get(free_cells, int(random_pos))
    }
}

game_over :: proc(self: ^Application) {
    self.is_game_over = true
    rl.sound_play(self, self.crash_sound)
}

draw :: proc(self: ^Application, dt: f32) -> (ok: bool) {
    rl.clear_color(self, rl.COLOR_BLACK)

    // Get screen bounds in camera units
    min_bounds, max_bounds := rl.camera_get_bounds(&self.ctx.camera)
    world_width := max_bounds.x * 2.0
    world_height := max_bounds.y * 2.0

    // Draw background
    rl.draw_sprite(
        self,
        self.background_texture,
        { 0.0, 0.0 },
        rl.COLOR_WHITE,
        size = { world_width, world_height },
        tile_count = { world_width/2, world_height/2 },
        z_index = -1,
    )

    if !self.is_game_over {
        self.tick_timer -= dt
        if self.tick_timer <= 0 {
            self.snake.direction = self.snake.next_direction

            next_part_pos := self.snake.body[0]
            self.snake.body[0] += self.snake.direction

            head_pos := self.snake.body[0]

            // Wrap head around screen edges
            if f32(head_pos.x) < min_bounds.x {
                self.snake.body[0].x = int(max_bounds.x)
                head_pos.x = int(max_bounds.x)
            } else if f32(head_pos.x) > max_bounds.x {
                self.snake.body[0].x = int(min_bounds.x)
                head_pos.x = int(min_bounds.x)
            }
            if f32(head_pos.y) < min_bounds.y {
                self.snake.body[0].y = int(max_bounds.y)
                head_pos.y = int(max_bounds.y)
            } else if f32(head_pos.y) > max_bounds.y {
                self.snake.body[0].y = int(min_bounds.y)
                head_pos.y = int(min_bounds.y)
            }

            // Check collision with itself
            for i in 1 ..< self.snake.length {
                curr_pos := self.snake.body[i]

                if curr_pos == head_pos {
                    game_over(self)
                }

                self.snake.body[i] = next_part_pos
                next_part_pos = curr_pos
            }

            // Check food collision (now after wrapping)
            if head_pos == self.food_pos {
                self.snake.length += 1
                self.snake.body[self.snake.length - 1] = next_part_pos
                place_food(self)
                rl.sound_play(self, self.eat_sound)
            }

            self.tick_timer = self.tick_rate + self.tick_timer
        }
    }

    head_size := rl.Vec2f{CELL_SIZE, CELL_SIZE}

    // Draw food
    food_pos := rl.Vec2f{
        math.round(f32(self.food_pos.x)),
        math.round(f32(self.food_pos.y)),
    }
    rl.draw_sprite(self, self.food_texture, food_pos, rl.COLOR_WHITE, head_size)

    // Draw snake
    for i in 0 ..< self.snake.length {
        part_pos := rl.Vec2f{
            math.round(f32(self.snake.body[i].x)),
            math.round(f32(self.snake.body[i].y)),
        }

        // Draw head differently
        if i == 0 {
            rl.draw_sprite(
                self, self.body_texture, part_pos, rl.COLOR_GREEN, head_size)
        } else {
            rl.draw_sprite(
                self, self.body_texture, part_pos, rl.COLOR_WHITE, head_size)
        }
    }

    // Walls
    // rl.draw_rect_outline(self,
    //     { 0.0, 0.0 }, { world_width, world_height }, 0.5, rl.COLOR_DARK_GREEN, z_index = 1)

    return true
}

event :: proc(self: ^Application, event: rl.Event) -> (ok: bool) {
    #partial switch &ev in event {
    case rl.Key_Pressed_Event:
        key := ev.key
        if (key == .W || key == .Up) && self.snake.direction != rl.VEC2I_DOWN {
            self.snake.next_direction = rl.VEC2I_UP
        } else if (key == .S || key == .Down) && self.snake.direction != rl.VEC2I_UP {
            self.snake.next_direction = rl.VEC2I_DOWN
        } else if (key == .A || key == .Left) && self.snake.direction != rl.VEC2I_RIGHT {
            self.snake.next_direction = rl.VEC2I_LEFT
        } else if (key == .D || key == .Right) && self.snake.direction != rl.VEC2I_LEFT {
            self.snake.next_direction = rl.VEC2I_RIGHT
        }

        if self.is_game_over && key == .Space {
            restart(self)
        }
    }
    return true
}

quit :: proc(self: ^Application) {
    rl.sound_destroy(self, self.eat_sound)
    rl.sound_destroy(self, self.crash_sound)

    rl.texture_destroy(self, self.background_texture)
    rl.texture_destroy(self, self.body_texture)
    rl.texture_destroy(self, self.food_texture)
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
