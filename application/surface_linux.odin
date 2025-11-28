#+build linux
package application

// Core
import "vendor:glfw"

// Local packages
import "../gpu"

_window_get_gpu_surface :: proc(
    window: Window,
    instance: gpu.Instance,
    loc := #caller_location,
) -> (
    surface: gpu.Surface,
    ok: bool,
) #optional_ok {
    impl := _window_get_impl(window, loc)

    descriptor: gpu.Surface_Descriptor
    switch glfw.GetPlatform() {
    case glfw.PLATFORM_WAYLAND:
        descriptor.label = "Wayland Surface"
        descriptor.target = gpu.Surface_Source_Wayland_Surface {
            display = glfw.GetWaylandDisplay(),
            surface = glfw.GetWaylandWindow(impl.handle),
        }
    case glfw.PLATFORM_X11:
        descriptor.label = "Xlib Window"
        descriptor.target = gpu.Surface_Source_Xlib_Window {
            display = glfw.GetX11Display(),
            window  = u64(glfw.GetX11Window(impl.handle)),
        }
    case:
        panic("Unsupported platform", loc)
    }

    return gpu.instance_create_surface(instance, descriptor, loc)
}
