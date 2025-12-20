package renderlink

// Core
import "base:runtime"

// Local libs
import app "../application"
import "../libs/gpu"

Texture :: distinct Handle

Texture_Format :: gpu.Texture_Format
Filter_Mode    :: gpu.Filter_Mode
Address_Mode   :: gpu.Address_Mode
Dimensions     :: gpu.Extent_3D

Texture_Impl :: struct {
    device:       gpu.Device,
    texture:      gpu.Texture,
    view:         gpu.Texture_View,
    sampler:      gpu.Sampler,
    bind_group:   gpu.Bind_Group, // bindable texture?
    label:        String_Buffer_Small,
    format:       Texture_Format,
    dimensions:   Dimensions,
    address_mode: Address_Mode,
}

Texture_Info :: struct {
    label:           string,
    width:           u32,
    height:          u32,
    format:          Texture_Format,
    mip_level_count: u32,
    filter_mode:     Filter_Mode,
    address_mode:    Address_Mode,
}

DEFAULT_TEXTURE_INFO :: Texture_Info {
    label           = "",
    mip_level_count = 1,
    filter_mode     = .Nearest,
    address_mode    = .Clamp_To_Edge,
}

load_texture :: proc(
    self: ^Context,
    filename: string,
    info := DEFAULT_TEXTURE_INFO,
) -> (
    texture: Texture,
    ok: bool,
) #optional_ok {
    ta := context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    data := app.load_file(filename, ta) or_return
    return load_texture_from_memory(self, data, info)
}

load_texture_from_memory :: proc(
    self: ^Context,
    data: []u8,
    info := DEFAULT_TEXTURE_INFO,
) -> (
    texture: Texture,
    ok: bool,
) #optional_ok {
    ta := context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    img := load_image_from_memory(data, .Rgb_Alpha, ta) or_return
    return load_texture_from_image(self, img, info)
}

load_texture_from_image :: proc(
    self: ^Context,
    img: Image,
    info := DEFAULT_TEXTURE_INFO,
) -> (
    texture: Texture,
    ok: bool,
) #optional_ok {
    texture_format := img.format

    width := img.size.x
    height := img.size.y
    dimensions := gpu.Extent_3D { width, height, 1 }

    // Create the GPU texture
    texture_desc := gpu.Texture_Descriptor {
        label           = info.label if len(info.label) > 0 else "",
        usage           = { .Texture_Binding, .Copy_Dst },
        dimension       = .D2,
        size            = dimensions,
        format          = texture_format,
        mip_level_count = 1,
        sample_count    = 1,
    }

    gpu_texture := gpu.device_create_texture(self.base.device, texture_desc)
    ensure(gpu_texture != nil, "Failed to create GPU texture")

    // Upload texture data to GPU
    bytes_per_row := width * u32(img.channels)
    rows_per_image := height

    destination := gpu.Texel_Copy_Texture_Info {
        texture   = gpu_texture,
        mip_level = 0,
        origin    = {0, 0, 0},
        aspect    = .All,
    }

    data_layout := gpu.Texel_Copy_Buffer_Layout {
        offset         = 0,
        bytes_per_row  = bytes_per_row,
        rows_per_image = rows_per_image,
    }

    gpu.queue_write_texture(self.base.queue, destination, img.pixels, data_layout, dimensions)

    // Create texture view
    view_desc := gpu.Texture_View_Descriptor {
        label             = info.label if len(info.label) > 0 else "",
        format            = texture_format,
        dimension         = .D2,
        base_mip_level    = 0,
        mip_level_count   = 1,
        base_array_layer  = 0,
        array_layer_count = 1,
        aspect            = .All,
    }

    texture_view := gpu.texture_create_view(gpu_texture, view_desc)
    ensure(texture_view != nil, "Failed to create texture view")

    sampler_desc := gpu.Sampler_Descriptor {
        label          = info.label if len(info.label) > 0 else "label",
        address_mode_u = info.address_mode,
        address_mode_v = info.address_mode,
        address_mode_w = info.address_mode,
        mag_filter     = info.filter_mode,
        min_filter     = info.filter_mode,
        mipmap_filter  = .Linear,
        lod_min_clamp  = 0.0,
        lod_max_clamp  = 32.0,
        compare        = .Undefined,
        anisotropy_clamp = 1,
    }

    sampler := gpu.device_create_sampler(self.base.device, sampler_desc)
    ensure(sampler != nil, "Failed to create sampler")

    impl := Texture_Impl {
        device       = self.base.device,
        texture      = gpu_texture,
        view         = texture_view,
        sampler      = sampler,
        format       = texture_format,
        dimensions   = dimensions,
        address_mode = info.address_mode,
    }

    if len(info.label) > 0 {
        string_buffer_init(&impl.label, info.label)
    }

    texture_handle := pool_create(&self.textures, impl)
    ensure(handle_is_valid(texture_handle))

    return Texture(from_handle(texture_handle)), true
}

texture_destroy :: proc(ctx: ^Context, texture: Texture) {
    handle := to_handle(texture)
    assert(handle_is_valid(handle), "Invalid texture handle")
    texture_impl := pool_get(&ctx.textures, handle)
    gpu.release(texture_impl.sampler)
    gpu.release(texture_impl.view)
    gpu.release(texture_impl.texture)
    if texture_impl.bind_group != nil {
        gpu.release(texture_impl.bind_group)
    }
    pool_remove(&ctx.textures, handle)
}

texture_dimensions :: proc(ctx: ^Context, texture: Texture) -> Dimensions {
    impl := _texture_get_impl(ctx, texture)
    return impl.dimensions
}

texture_is_valid :: #force_inline proc(texture: Texture) -> bool {
    return handle_is_valid(to_handle(texture))
}

@(private)
_texture_get_impl :: proc(ctx: ^Context, texture: Texture) -> ^Texture_Impl {
    assert(texture_is_valid(texture), "Invalid texture handle")
    return pool_get(&ctx.textures, to_handle(texture))
}
