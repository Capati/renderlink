#+build darwin
package application

// Core
import NS "core:sys/darwin/Foundation"
import CA "vendor:darwin/QuartzCore"
import "vendor:glfw"

// Local packages
import "../gpu"

_window_get_gpu_surface :: proc(
    window: Window,
    instance: gpu.Instance,
    loc := #caller_location,
) -> gpu.Surface {
    impl := _window_get_impl(window, loc)

    nativeWindow := (^NS.Window)(glfw.GetCocoaWindow(window))

    metalLayer := CA.MetalLayer.layer()
    defer metalLayer->release()

    nativeWindow->contentView()->setLayer(metalLayer)

    descriptor := gpu.Surface_Descriptor {
        label = "Metal Layer",
        target = gpu.SurfaceSourceMetalLayer {
            layer = metalLayer,
        },
    }

    return gpu.instance_create_surface(instance, descriptor, loc)
}
