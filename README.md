# Odin GPU

<p align="left">
  <a href="https://opensource.org/licenses/MIT">
    <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT" height="25">
  </a>
  <a href="https://odin-lang.org/">
    <img src="https://img.shields.io/badge/Language-Odin-blue" alt="Language: Odin" height="25">
  </a>
  <a href="#status">
    <img src="https://img.shields.io/badge/Status-WIP-orange" alt="Status: WIP" height="25">
  </a>
</p>

A modern graphics API wrapper for [Odin Language][], inspired by the [WebGPU][] specification. This
library provides portable abstractions over Vulkan, DirectX 12, Metal, OpenGL, and WebGPU
backends.

## Status

🚧 **This project is extremely work-in-progress.**

> I was tired of hitting bugs in wgpu… so I decided to write my own bugs instead.

## Overview

The current goal is to follow the WebGPU specification closely, using it as a foundation for a
modern API. However, it`s not intended to be a strict clone of the spec, if something doesn't fit
well with the intended usage, we'll change it.

In practice, the early API stages will probably match WebGPU pretty closely. Over time, naming,
structure, and even core concepts may shift as things stabilize for better patterns. A future
refactor is not only possible, it's expected.

### Shader Model

One major deviation from the WebGPU specification is the shader language. WebGPU mandates WGSL as
its shading language, but Odin GPU does **not** require WGSL for native backends.

WGSL is only used when targeting WebAssembly/WebGPU in the browser. For native platforms, you’re
free to bring your own shaders in whatever format or language your backend supports (SPIR-V, GLSL,
DXIL, MSL and WGSL).

That said, we **strongly recommend using [Slang](https://github.com/shader-slang/slang)**. Slang
lets you write modern HLSL-style shaders and compile them to multiple targets. The current examples
is using slang to compile for the supported backends.

So the short version:

- WGSL: browser only  
- Native: use whatever you want  
- Recommendation: use Slang and let it handle the compiled parts

### Bind Group Layout

Unlike WebGPU, Odin GPU **requires explicit bind group layout creation**. The WebGPU convenience feature `"auto"` and the method `renderPipelineGetBindGroupLayout()` are **not available** in this library.

**Why the difference?**

WebGPU's `"auto"` layout allows the API to infer bind group layouts from shader reflection at
pipeline creation time. While convenient, this approach:
- Hides resource binding structure from the application
- Can make debugging and optimization more difficult
- Doesn't fit well with certain native backend patterns

**What this means for you:**

You must explicitly create and provide `BindGroupLayout` objects when creating pipelines and bind
groups. This gives you full control over resource bindings and makes the relationship between
shaders and resources explicit in your code.

```odin
// 1. Create the bind group layout first
bind_group_layout := gpu.device_create_bind_group_layout(
    device,
    {
        label = "My Bind Group Layout",
        entries = {
            {
                binding = 0,
                visibility = {.Vertex},
                type = gpu.Buffer_Binding_Layout {
                    type = .Uniform,
                    has_dynamic_offset = false,
                    min_binding_size = size_of(la.Matrix4f32),
                },
            },
        },
    },
)
defer gpu.release(bind_group_layout)

// 2. Use it to create the pipeline layout
pipeline_layout := gpu.device_create_pipeline_layout(
    device,
    {
        label = "My Pipeline Layout",
        bind_group_layouts = {bind_group_layout},
    },
)
defer gpu.release(pipeline_layout)

// 3. Create the render pipeline with the explicit layout
render_pipeline := gpu.device_create_render_pipeline(
    device,
    {
        label = "My Render Pipeline",
        layout = pipeline_layout,
        vertex = {
            // vertex state configuration
        },
        // ... rest of pipeline descriptor
    },
)

// 4. Later, create bind groups using the same layout
uniform_bind_group := gpu.device_create_bind_group(
    device,
    {
        layout = bind_group_layout,  // Same layout used for pipeline
        entries = {
            // actual resource bindings
        },
    },
)
```

While this requires more upfront code, it promotes better understanding of your resource layout and
can lead to more maintainable graphics code.

## Roadmap

| Feature | Status | Notes |
|---------|--------|-------|
| **Core API** |
| Core API Layout | 🟡 In Progress | Basic types exist, API not yet stable |
| Memory Management | 🔴 Todo | Allocation strategies and lifetime management |
| Error Handling | 🔴 Todo | Odin-style error patterns |
| **Backends** |
| Vulkan | 🟡 In Progress | Main priority |
| DirectX 12 | 🟡 In Progress | Windows support |
| Metal | 🔴 Not Started | Might rely on MoltenVK first |
| OpenGL | 🟡 In Progress | Fallback backend? |
| WebGPU | 🟡 In Progress | WASM support |
| **Advanced** |
| Ray Tracing | ⚪ Future | Not currently planned |

## Examples

Explore [all examples](./examples) to see the implementation in action.

## Contributing

Contributions, feedback, and memes are welcome!

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.

---

<p align="center">
  Made with ❤️ and frustration by developers who just want graphics to work
</p>

[Odin Language]: https://odin-lang.org/
[WebGPU]: https://www.w3.org/TR/webgpu/
