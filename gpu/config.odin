package gpu

// Detect and define BACKEND_DEFAULT based on the target platform.
when ODIN_OS == .Windows {
    BACKEND_DEFAULT :: Backend.Dx12
} else when ODIN_OS == .Darwin {
    BACKEND_DEFAULT :: Backend.Metal
} else when ODIN_OS == .Linux {
    BACKEND_DEFAULT :: Backend.Vulkan
} else when ODIN_OS == .JS {
    BACKEND_DEFAULT :: Backend.WebGPU
} else {
    BACKEND_DEFAULT :: Backend.Vulkan
}
