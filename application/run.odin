#+build !js
package application

// Local libs
import application "../application"

run :: proc(app: ^Application) {
    assert(!app.prepared, "Application already initialized")

    // Initialize the user application
    if app.callbacks.init != nil {
        if res := app.callbacks.init(app); !res {
            destroy(app)
            return
        }
    }

    defer {
        if app.callbacks.quit != nil {
            app.callbacks.quit(app)
        }
    }

    // Set up window callbacks
    _window_setup_callbacks(app.window)

    refresh_rate := f64(window_get_refresh_rate(app.window))
    assert(refresh_rate != 0)
    margin_ms := 0.5 // Wake up early for busy wait accuracy
    target_frame_time_ms := 1000.0 / refresh_rate
    timer_init(&app.timer, margin_ms, target_frame_time_ms)

    app.prepared = true
    app.running = true

    MAIN_LOOP: for app.running {
        _window_process_events(app.window)

        // Does events requested exit?
        if !app.running {
            break
        }

        application.keyboard_update(app)

        timer_begin_frame(&app.timer)

        // Application iteration
        if app.callbacks.draw != nil {
            if !app.callbacks.draw(app, f32(timer_get_delta(&app.timer))) {
                app.running = false
                break MAIN_LOOP
            }
        }

        // Show current backend and FPS
        when ODIN_DEBUG {
            if timer_get_fps_update(&app.timer) {
                window_impl := _window_get_impl(app.window)

                // Create a new buf for the custom title
                @(static)
                buf: String_Buffer_Small
                string_buffer_init(&buf, string_buffer_get_string(&window_impl.title_buf))
                string_buffer_append(&buf, " - [ ")
                string_buffer_append(&buf, get_backend_string(app))
                string_buffer_append(&buf, " ")
                fps_buf: [4]u8
                string_buffer_append_f64(&buf, fps_buf[:], timer_get_fps(&app.timer))
                string_buffer_append(&buf, " ]")
                window_set_title(app.window, string_buffer_get_cstring(&buf))
            }
        }

        timer_end_frame(&app.timer)
        // gpu_pace_frame(app.gpu, &app.timer)
    }
}
