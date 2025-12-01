#+build js
package application

// Core
import "base:runtime"
import "core:sys/wasm/js"

// Local packages
import "../gpu"

CANVAS_ID_DEFAUULT :: "#canvas"

Window_Impl :: struct {
    using _base: Window_Base,
    canvas_id:   string,
}

@(require_results)
_window_create :: proc(
    mode: Video_Mode,
    title: string,
    style: Window_Styles,
    state: Window_State,
    allocator: runtime.Allocator,
    loc := #caller_location,
) -> Window {
    assert(mode.width >= MIN_CLIENT_WIDTH, "Invalid window width", loc)
    assert(mode.height >= MIN_CLIENT_HEIGHT, "Invalid window height", loc)

    impl := new(Window_Impl, allocator)
    ensure(impl != nil, "Failed to allocate the window implementation", loc)

    // Default fullscreen video mode
    desktop_mode := get_video_mode()

    mode := mode

    if state == .Fullscreen {
        // For web, fullscreen means using the full browser viewport
        mode = desktop_mode
    } else {
        mode.refresh_rate = desktop_mode.refresh_rate // ensure valid refresh rate
    }

    impl.custom_context = context
    impl.allocator = allocator
    impl.resize_callbacks.allocator = allocator
    impl.settings = { style, state }
    impl.canvas_id = CANVAS_ID_DEFAUULT
    impl.mode = mode

    // Initial size calculation
    impl.aspect = f32(mode.width) / f32(mode.height)

    return cast(Window)impl
}

_window_destroy :: proc(window: Window) {
    impl := _window_get_impl(window)
    context = impl.custom_context
    _window_cleanup_callbacks(window)
    delete(impl.resize_callbacks)
    free(impl)
}

_window_process_events :: proc(window: Window) {
}

_window_filter_event :: proc "contextless" (impl: ^Window_Impl, event: ^Event) {
}

@(require_results)
_window_poll_event :: proc(window: Window, event: ^Event) -> (ok: bool) {
    return
}

@(require_results)
_window_get_handle :: proc "contextless" (window: Window) -> string {
    impl := _window_get_impl(window)
    return impl.canvas_id
}

_window_get_size :: proc(window: Window) -> (size: Vec2u) {
    // Get body dimensions as proxy for viewport
    body_rect := js.get_bounding_client_rect("body")

    // Get device pixel ratio
    dpi := js.device_pixel_ratio()

    size.x = u32(f64(body_rect.width) * dpi)
    size.y = u32(f64(body_rect.height) * dpi)

    return
}

@(require_results)
_window_get_title :: proc(window: Window) -> string {
    return ""
}

_window_set_title :: proc(window: Window, title: string) {
}

_window_switch_to_fullscreen :: proc (window: Window, mode: Video_Mode) {
}

@(require_results)
_window_get_gpu_surface :: proc(
    window: Window,
    instance: gpu.Instance,
) -> (
    gpu.Surface,
    bool,
) #optional_ok {
    impl := _window_get_impl(window)
    return gpu.instance_create_surface(
        instance,
        gpu.Surface_Descriptor {
            target = gpu.Surface_Source_Canvas_HTML_Selector{selector = impl.canvas_id},
        },
    )
}

// -----------------------------------------------------------------------------
// @(private)
// -----------------------------------------------------------------------------

@(private, require_results)
_window_get_user_pointer :: #force_inline proc "c" (
    handle: js.Event,
    loc := #caller_location,
) -> ^Window_Impl {
    window := cast(^Window_Impl)handle.user_data
    assert_contextless(window != nil, "Invalid Window pointer", loc)
    return window
}

@(private)
_window_setup_callbacks :: proc(window: Window) {
    impl := _window_get_impl(window)

    // Window/document events
    ensure(js.add_window_event_listener(.Unload, impl, _window_unload_callback))
    ensure(js.add_window_event_listener(.Resize, impl, _window_resize_callback))
    ensure(js.add_window_event_listener(.Visibility_Change, impl, _window_visibility_callback))

    // Canvas-specific events
    // ensure(js.add_event_listener("canvas", .Click, impl, _window_mouse_button_callback))
    ensure(js.add_event_listener("canvas", .Mouse_Down, impl, _window_mouse_button_callback))
    ensure(js.add_event_listener("canvas", .Mouse_Up, impl, _window_mouse_button_callback))
    ensure(js.add_event_listener("canvas", .Mouse_Move, impl, _window_mouse_move_callback))
    ensure(js.add_event_listener("canvas", .Wheel, impl, _window_scroll_callback))
    ensure(js.add_event_listener("canvas", .Context_Menu, impl, _window_context_menu_callback))

    // Key events (typically handled at window level)
    ensure(js.add_window_event_listener(.Key_Down, impl, _window_key_callback))
    ensure(js.add_window_event_listener(.Key_Up, impl, _window_key_callback))

    // Focus events
    // js.add_event_listener(impl.canvas_id, .Focus, impl, _window_focus_callback)
    // js.add_event_listener(impl.canvas_id, .Blur, impl, _window_focus_callback)
}

@(private)
_window_cleanup_callbacks :: proc(window: Window) {
    impl := _window_get_impl(window)
    js.remove_window_event_listener(.Unload, impl, _window_unload_callback)
    js.remove_window_event_listener(.Resize, impl, _window_resize_callback)
    js.remove_window_event_listener(.Visibility_Change, impl, _window_visibility_callback)
    // js.remove_event_listener(impl.canvas_id, .Click, impl, _window_mouse_button_callback)
    js.remove_event_listener(impl.canvas_id, .Mouse_Down, impl, _window_mouse_button_callback)
    js.remove_event_listener(impl.canvas_id, .Mouse_Up, impl, _window_mouse_button_callback)
    js.remove_event_listener(impl.canvas_id, .Mouse_Move, impl, _window_mouse_move_callback)
    js.remove_event_listener(impl.canvas_id, .Wheel, impl, _window_scroll_callback)
    js.remove_event_listener(impl.canvas_id, .Context_Menu, impl, _window_context_menu_callback)
    js.remove_window_event_listener(.Key_Down, impl, _window_key_callback)
    js.remove_window_event_listener(.Key_Up, impl, _window_key_callback)
    // js.remove_event_listener(impl.canvas_id, .Focus, impl, _window_focus_callback)
    // js.remove_event_listener(impl.canvas_id, .Blur, impl, _window_focus_callback)
}

@(private)
_window_unload_callback :: proc(event: js.Event) {
    // js.alert("teste")
}

@(private)
_window_resize_callback :: proc(event: js.Event) {
    impl := _window_get_user_pointer(event)
    window := cast(Window)impl

    new_size := window_get_size(window)

    // First execute all registered resize callbacks immediately.
    for &cb in impl.resize_callbacks {
        if cb.callback != nil {
            cb.callback(window, new_size, cb.userdata)
        }
    }

    dispatch_event(impl.app, Resize_Event{ new_size })
}

@(private)
_window_visibility_callback :: proc(event: js.Event) {
    impl := cast(^Window_Impl)event.user_data
    // window := cast(Window)impl
    is_visible := event.visibility_change.is_visible
    dispatch_event(impl.app, Restored_Event{ restored = is_visible })
}

@(private)
_window_mouse_button_callback :: proc(event: js.Event) {
    impl := cast(^Window_Impl)event.user_data
    // window := cast(Window)impl

    dpi := js.device_pixel_ratio()

    pos := Vec2f{
        cast(f32)(f64(event.mouse.offset.x) * dpi),
        cast(f32)(f64(event.mouse.offset.y) * dpi),
    }

    button: Mouse_Button
    switch event.mouse.button {
    case 0: button = .Left
    case 1: button = .Middle
    case 2: button = .Right
    case: button = .Left // fallback
    }

    #partial switch event.kind {
    case .Mouse_Down, .Click:
        dispatch_event(impl.app, Mouse_Button_Pressed_Event{button = button, pos = pos})
    case .Mouse_Up:
        dispatch_event(impl.app, Mouse_Button_Released_Event{button = button, pos = pos})
    }
}

@(private)
_window_mouse_move_callback :: proc(event: js.Event) {
    impl := cast(^Window_Impl)event.user_data
    // context = impl.custom_context
    // window := cast(Window)impl

    dpi := js.device_pixel_ratio()

    pos := Vec2f{
        cast(f32)(f64(event.mouse.offset.x) * dpi),
        cast(f32)(f64(event.mouse.offset.y) * dpi),
    }

    // Determine which buttons are currently pressed using button bit set
    button: Mouse_Button = .Unknown
    action: Input_Action = .None

    if 0 in event.mouse.buttons {  // Left button
        button = .Left
        action = .Pressed
    } else if 2 in event.mouse.buttons {  // Right button
        button = .Right
        action = .Pressed
    } else if 1 in event.mouse.buttons {  // Middle button
        button = .Middle
        action = .Pressed
    }

    dispatch_event(impl.app, Mouse_Moved_Event{
        pos = pos,
        button = button,
        action = action,
    })
}

@(private)
_window_scroll_callback :: proc(event: js.Event) {
    impl := cast(^Window_Impl)event.user_data
    // window := cast(Window)impl

    delta := Vec2f{
        cast(f32)event.wheel.delta.x,
        cast(f32)event.wheel.delta.y,
    }
    dispatch_event(impl.app, Mouse_Wheel_Event(delta))
}

@(private)
_window_context_menu_callback :: proc(event: js.Event) {
    impl := cast(^Window_Impl)event.user_data
    // window := cast(Window)impl

    dpi := js.device_pixel_ratio()

    // Get mouse position for context menu event
    pos := Vec2f{
        cast(f32)(f64(event.mouse.offset.x) * dpi),
        cast(f32)(f64(event.mouse.offset.y) * dpi),
    }

    // Dispatch right-click event for context menu
    dispatch_event(impl.app, Mouse_Button_Pressed_Event{
        button = .Right,
        pos = pos,
    })
}

@(private)
_window_key_callback :: proc(_event: js.Event) {
    impl := cast(^Window_Impl)_event.user_data
    // context = impl.custom_context
    // window := cast(Window)impl

    key := _to_key(_event.key.key)

    event := Key_Event{
        key      = key,
        scancode = Scancode(_to_scancode(_event.key.code)),
        ctrl     = _event.key.ctrl,
        shift    = _event.key.shift,
        alt      = _event.key.alt,
    }

    app := impl.app

    #partial switch _event.kind {
    case .Key_Down:
        // Update keyboard state
        if key != .Unknown {
            app.keyboard.current[key] = true
            // Only set as last pressed if it wasn't already pressed (avoid repeat events)
            if !app.keyboard.previous[key] {
                app.keyboard.last_key_pressed = key
            }
        }

        dispatch_event(impl.app, Key_Pressed_Event(event))
    case .Key_Up:
        // Update keyboard state
        if key != .Unknown {
            app.keyboard.current[key] = false
            app.keyboard.last_key_released = key
        }

        dispatch_event(impl.app, Key_Released_Event(event))
    }
}

// @(private)
// _window_focus_callback :: proc(event: js.Event) {
// }
