package application

// Core
import "base:runtime"
import "core:log"
import intr "base:intrinsics"

// Libs
import "../gpu"

_ :: log
_ :: gpu

App_Init_Callback :: #type proc(app: ^Application) -> bool

App_Draw_Callback :: #type proc(app: ^Application, dt: f32) -> bool

App_Event_Callback :: #type proc(app: ^Application, event: Event) -> bool

App_Quit_Callback :: #type proc(app: ^Application)

Settings :: struct {
    using window: Window_Settings,
    using gpu:    GPU_Settings,
}

SETTINGS_DEFAULT :: Settings {
    window = WINDOW_SETTINGS_DEFAULT,
    gpu    = GPU_SETTINGS_DEFAULT,
}

Application_Callbacks :: struct {
    init:  App_Init_Callback,
    draw:  App_Draw_Callback,
    event: App_Event_Callback,
    quit:  App_Quit_Callback,
}

Application :: struct {
    /* Initialization */
    custom_context:   runtime.Context,
    allocator:        runtime.Allocator,
    window:           Window,
    settings:         Settings,

    // Callbacks
    callbacks:        Application_Callbacks,

    // State
    // title_buf:     String_Buffer,
    timer:            Timer,
    keyboard:      Keyboard_State,
    mouse:         Mouse_State,
    exit_key:         Key,
    running:          bool,
    minimized:        bool,
    prepared:         bool,

    // GPU Context
    instance:         gpu.Instance,
    surface:          gpu.Surface,
    adapter:          gpu.Adapter,
    device:           gpu.Device,
    queue:            gpu.Queue,
    caps:             gpu.Surface_Capabilities,
    config:           gpu.Surface_Configuration,
    is_srgb:          bool,
    framebuffer_size: Vec2u,
}

// Opens a window and initializes the application context.
//
// Inputs:
//
// - `$T` - The application type to create. Must be a subtype of the base
//   `Application` struct (e.g., `#subtype app: Application`).
// - `mode` - Video mode configuration (resolution, fullscreen, etc.)
// - `window_title` - Title displayed in the window's title bar
// - `callbacks` - Application lifecycle callbacks (init, step, event and quit)
// - `settings` - Optional window and GPU configuration settings (defaults to SETTINGS_DEFAULT)
// - `allocator` - Memory allocator to use (defaults to context.allocator)
init :: proc(
    app: $T/^Application,
    mode: Video_Mode,
    window_title: string,
    callbacks: Application_Callbacks,
    settings := SETTINGS_DEFAULT,
    allocator := context.allocator,
    loc := #caller_location,
) {
    // Allocate the custom type T with proper size
    // app := cast(^Application)new(T, allocator)
    ensure(app != nil, "Failed to allocate the application context", loc)

    app := cast(^Application)app

    // Initialize core application state
    app.custom_context = context
    app.allocator = allocator
    app.settings = settings
    app.callbacks = callbacks

    // Create window
    app.window = window_create(mode, window_title, settings.window, allocator, loc)
    window_set_application(app.window, app)

    when ODIN_DEBUG {
        app.exit_key = .Escape
    }

    instance_descriptor: gpu.Instance_Descriptor

    when ODIN_DEBUG {
        instance_descriptor.flags = {.Debug, .Validation}
    }

    app.instance = gpu.create_instance(instance_descriptor)
    assert(app.instance != nil)

    // Create surface from window
    app.surface = window_get_gpu_surface(app.window, app.instance)

    // Request adapter
    adapter_options := gpu.Request_Adapter_Options {
        compatible_surface     = app.surface,
        power_preference       = app.settings.power_preference,
        force_fallback_adapter = app.settings.force_fallback_adapter,
    }

    gpu.instance_request_adapter(
        app.instance, adapter_options, { callback = on_adapter, userdata1 = app })

    on_adapter :: proc(
        status: gpu.Request_Adapter_Status,
        adapter: gpu.Adapter,
        message: string,
        userdata1: rawptr,
        userdata2: rawptr,
    ) {
        app := cast(^Application)userdata1
        context = app.custom_context

        // Validate adapter request
        if status != .Success || adapter == nil {
            log.panicf("Adapter request failed: [%v] %s", status, message)
        }

        app.adapter = adapter

        when ODIN_OS != .JS {
            runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
            ta := context.temp_allocator

            adapter_info := gpu.adapter_get_info(app.adapter)
            defer gpu.adapter_info_free_members(adapter_info)

            log.infof("Selected adapter:\n%s", gpu.adapter_info_string(adapter_info, ta))
        }

        uncaptured_error_callback :: proc(
            device: ^gpu.Device,
            type: gpu.Error_Type,
            message: string,
            userdata1: rawptr,
            userdata2: rawptr,
        ) {
            // context = runtime.default_context()
            // log.info(type)
            // log.info(message)
        }

        // Request device with specified requirements
        device_descriptor := gpu.Device_Descriptor {
            label = "Device",
            required_features = {.Clip_Distances},
            required_limits   = app.settings.required_limits,
            uncaptured_error_callback_info = {
                callback = uncaptured_error_callback,
            },
        }

        gpu.adapter_request_device(app.adapter, device_descriptor, {
            callback = on_device, userdata1 = app,
        })
    }

    on_device :: proc(
        status: gpu.Request_Device_Status,
        device: gpu.Device,
        message: string,
        userdata1: rawptr,
        userdata2: rawptr,
    ) {
        app := cast(^Application)userdata1
        context = app.custom_context

        // Validate device request
        if status != .Success || device == nil {
            log.panicf("Device request failed: [%v] %s", status, message)
        }

        app.device = device

        // Get default queue
        app.queue = gpu.device_get_queue(app.device)

        // Get surface capabilities
        app.caps = gpu.surface_get_capabilities(app.surface, app.adapter)

        // Determine best surface format
        preferred_format: gpu.Texture_Format
        if app.settings.desired_surface_format != .Undefined {
            // Check if desired format is supported
            for format in app.caps.formats {
                if app.settings.desired_surface_format == format {
                    preferred_format = format
                    break
                }
            }
        }

        // Fallback to first available format if desired format not found
        if preferred_format == .Undefined {
            preferred_format = app.caps.formats[0]
        }

        // Handle sRGB configuration
        app.is_srgb = gpu.texture_format_is_srgb(preferred_format)
        if app.settings.remove_srgb_from_surface && app.is_srgb {
            app.is_srgb = false
            preferred_format = gpu.texture_format_remove_srgb_suffix(preferred_format)
        }

        log.debugf("Preferred surface format: %v", preferred_format)

        // Determine present mode with validation
        present_mode := app.settings.desired_present_mode
        if present_mode == .Undefined {
            present_mode = .Fifo  // Safe default
        } else if present_mode != .Fifo {
            // Validate that desired present mode is supported
            mode_supported := false
            for mode in app.caps.present_modes {
                if present_mode == mode {
                    mode_supported = true
                    break
                }
            }

            if !mode_supported {
                log.warnf(
                    "Desired present mode %v not supported, falling back to %v", present_mode)
                present_mode = gpu.PRESENT_MODE_DEFAULT
            }
        }

        log.debugf("Selected present mode: %v", present_mode)

        // Get current window size
        app.framebuffer_size = window_get_size(app.window)

        device_features := gpu.device_get_features(app.device)

        // Configure surface usage based on format capabilities
        surface_format_features := gpu.texture_format_guaranteed_format_features(
            preferred_format, device_features)

        surface_allowed_usages := surface_format_features.allowed_usages
        // DX12 backend limitation: remove TextureBinding usage for surface textures
        if .Texture_Binding in surface_allowed_usages {
            surface_allowed_usages -= { .Texture_Binding }
        }

        // Create final surface configuration
        app.config = gpu.Surface_Configuration {
            usage        = { .Render_Attachment },
            format       = preferred_format,
            width        = app.framebuffer_size.x,
            height       = app.framebuffer_size.y,
            present_mode = present_mode,
            alpha_mode   = .Auto,
        }

        gpu.surface_configure(app.surface, app.device, app.config)

        // window_add_resize_callback(app.window, { gpu_resize_surface, app.gpu })

        // Initialization complete - start main application loop
        run(app)
    }
}

destroy :: proc(app: ^Application) {
    assert(app != nil, "Invalid application")
    context = app.custom_context

    gpu.surface_capabilities_free_members(app.caps)

    gpu.queue_release(app.queue)
    gpu.device_release(app.device)
    gpu.adapter_release(app.adapter)
    gpu.surface_release(app.surface)

    when ODIN_DEBUG && ODIN_OS != .JS {
        // gpu.check_for_memory_leaks(app.instance)
    }

    gpu.instance_release(app.instance)

    window_destroy(app.window)

    // free(app)
}

set_callbacks :: proc "contextless" (app: ^Application, callbacks: Application_Callbacks) {
    app.callbacks = callbacks
}

@(require_results)
get_time :: proc(app: ^Application) -> f32 {
    return f32(timer_get_time(&app.timer))
}

@(require_results)
get_delta_time :: proc(app: ^Application) -> f32 {
    return f32(timer_get_delta(&app.timer))
}

dispatch_event :: proc "contextless" (app: ^Application, event: Event) {
    context = app.custom_context

    if app.callbacks.event != nil {
        if !app.callbacks.event(app, event) {
            app.running = false
        }
    }

    when ODIN_DEBUG && ODIN_OS != .JS {
        #partial switch &ev in event {
        case Key_Pressed_Event:
            if app.exit_key != .Unknown && app.exit_key == ev.key {
                app.running = false
                dispatch_event(app, Quit_Event{})
            }
        }
    }
}
