package application

// Core
import "base:runtime"
import "core:log"

// Opaque handle representing a `Window`.
Window :: distinct uintptr

// Bit flags for specifying the style of a window.

// These flags can be combined to define how a window should behave.
Window_Styles :: bit_set[Window_Style]
Window_Style :: enum {
    Centered,
    Resizable,
    Borderless,
}

WINDOW_STYLES_DEFAULT :: Window_Styles{.Centered, .Resizable}

// Represents the state of a window.
Window_State :: enum {
    Windowed,
    Fullscreen,
    Fullscreen_Borderless,
}

WINDOW_STATE_DEFAULT :: Window_State.Windowed

Window_Settings :: struct {
    styles: Window_Styles,
    state:  Window_State,
}

WINDOW_SETTINGS_DEFAULT :: Window_Settings {
    styles = WINDOW_STYLES_DEFAULT,
    state  = WINDOW_STATE_DEFAULT,
}

// Procedure type for handling window resize events.
//
// This procedure is called whenever the window is resized.
//
// Inputs:
//
// - `window` The window that was resized.
// - `size` The new size of the window's client area.
// - `userdata` User-defined data passed to the callback.
Window_Resize_Proc :: #type proc "contextless" (window: Window, size: Vec2u, userdata: rawptr)

MIN_CLIENT_WIDTH :: 1
MIN_CLIENT_HEIGHT :: 1

Window_Resize_Info :: struct {
    callback: Window_Resize_Proc,
    userdata: rawptr,
}

Window_Base :: struct {
    custom_context:   runtime.Context,
    allocator:        runtime.Allocator,
    app:              ^Application,
    settings:         Window_Settings,
    mode:             Video_Mode,
    title_buf:        String_Buffer_Small,
    size:             Vec2u,
    events:           Events,
    resize_callbacks: [dynamic]Window_Resize_Info,
    aspect:           f32,
    is_minimized:     bool,
    is_resizing:      bool,
    is_fullscreen:    bool,
}

@(require_results)
window_create :: proc(
    mode: Video_Mode,
    title: string,
    settings := WINDOW_SETTINGS_DEFAULT,
    allocator := context.allocator,
    loc := #caller_location,
) -> Window {
    assert(mode.width >= MIN_CLIENT_WIDTH, "Invalid window width")
    assert(mode.height >= MIN_CLIENT_HEIGHT, "Invalid window height")

    styles := settings.styles
    state := settings.state

    // Default fullscreen video mode
    desktop_mode := get_video_mode()

    mode := mode

    // Fullscreen style requires some tests
    if state == .Fullscreen {
        // Make sure that the chosen video mode is compatible
        if !video_mode_is_valid(mode) {
            log.warn("The requested video mode is not available, switching to default mode")
            mode = desktop_mode
        }
    } else {
        mode.refresh_rate = desktop_mode.refresh_rate // ensure valid refresh rate
    }

    return _window_create(mode, title, styles, state, allocator)
}

window_destroy :: _window_destroy

// @(require_results)
// window_poll_event :: proc(window: Window, event: ^Event) -> (ok: bool) {
//     impl := _window_get_impl(window)
//     if events_empty(&impl.events) {
//         _window_process_events(window)
//     }
//     event^, ok = events_poll(&impl.events)
//     if ok {
//         _window_filter_event(impl, event)
//         when ODIN_DEBUG {
//             #partial switch &ev in event {
//             case Key_Pressed_Event:
//                 if ev.key == .Escape {
//                     events_push(&impl.events, Quit_Event{})
//                 }
//             }
//         }
//     }
//     return
// }

window_get_size :: _window_get_size

@(require_results)
window_is_resizing :: proc(window: Window) -> bool {
    impl := _window_get_impl(window)
    return impl.is_resizing
}

// window_switch_to_fullscreen :: _window_switch_to_fullscreen

window_get_gpu_surface :: _window_get_gpu_surface

window_get_refresh_rate :: proc(window: Window) -> u32 {
    impl := _window_get_impl(window)
    return impl.mode.refresh_rate
}

window_get_title :: _window_get_title

window_set_title :: _window_set_title

window_set_application :: proc(window: Window, app: ^Application) {
    impl := _window_get_impl(window)
    impl.app = app
}

// -----------------------------------------------------------------------------
// @(private)
// -----------------------------------------------------------------------------

@(private, require_results)
_window_get_impl :: #force_inline proc "contextless" (
    window: Window,
    loc := #caller_location,
) -> ^Window_Impl {
    impl := cast(^Window_Impl)window
    assert_contextless(impl != nil, "Invalid window handle", loc)
    return impl
}
