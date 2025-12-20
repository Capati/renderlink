#+build windows
package application

// Core
import win32 "core:sys/windows"

// Vendor
import "vendor:glfw"

// Local packages
import "../libs/gpu"

_window_get_gpu_surface :: proc(
    window: Window,
    instance: gpu.Instance,
    loc := #caller_location,
) -> gpu.Surface {
    impl := _window_get_impl(window, loc)

    descriptor := gpu.Surface_Descriptor {
        label = "Windows HWND",
        target = gpu.Surface_Source_Windows_HWND {
            hinstance = win32.GetModuleHandleW(nil),
            hwnd = glfw.GetWin32Window(impl.handle),
        },
    }

    return gpu.instance_create_surface(instance, descriptor, loc)
}
