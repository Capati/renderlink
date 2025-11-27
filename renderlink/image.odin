package renderlink

// Core
import "base:runtime"
import "core:bytes"
import "core:log"
import "core:mem"

// Image loaders
import "core:image"
import "core:image/bmp"
import "core:image/jpeg"
import "core:image/png"
import "core:image/tga"

_ :: png
_ :: tga
_ :: jpeg
_ :: bmp

// Local libs
import app "../application"

Image_Channel :: enum {
    Default,
    Grey,
    Grey_Alpha,
    Rgb,
    Rgb_Alpha,
}

Image :: struct {
    pixels:    []u8,
    size:      Vec2u,
    format:    Texture_Format,
    channels:  Image_Channel,
    allocator: mem.Allocator,
}

image_free :: proc(self: ^Image) {
    if self.pixels != nil {
        delete(self.pixels, self.allocator)
        self.pixels = nil
    }
}

load_image_from_filename :: proc(
    filename: string,
    desired_channels: Image_Channel = .Rgb_Alpha,
    allocator := context.allocator,
) -> (
    img: Image,
    ok: bool,
) {
    ta := context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    if data, read_ok := app.load_file(filename, ta); read_ok {
        return load_image_from_memory(data, desired_channels, allocator)
    }
    return
}

load_image_from_memory :: proc(
    buf: []u8,
    desired_channels: Image_Channel = .Rgb_Alpha,
    allocator := context.allocator,
) -> (
    img: Image,
    ok: bool,
) {
    ta := context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == ta)
    core_img, err := image.load_from_bytes(buf, allocator = ta)
    if err != nil {
        log.errorf("Failed to load image: %v", err)
        return
    }
    return _image_from_core_image(core_img, desired_channels, allocator)
}

load_image :: proc {
    load_image_from_filename,
    load_image_from_memory,
}

calculate_image_byte_size :: #force_inline proc(
    width, height: u32,
    channels: Image_Channel,
) -> u32 {
    return width * height * u32(channels)
}

@(private)
_image_from_core_image :: proc(
    core_img: ^image.Image,
    desired_channels: Image_Channel,
    allocator: mem.Allocator,
) -> (
    img: Image,
    ok: bool,
) {
    width := u32(core_img.width)
    height := u32(core_img.height)
    src_channels := core_img.channels

    // Determine source channel layout
    src_channel_type: Image_Channel
    switch src_channels {
    case 1: src_channel_type = .Grey
    case 2: src_channel_type = .Grey_Alpha
    case 3: src_channel_type = .Rgb
    case 4: src_channel_type = .Rgb_Alpha
    case:
        log.errorf("Unsupported channel count: %d", src_channels)
        return
    }

    target_channels := desired_channels
    if target_channels == .Default {
        target_channels = src_channel_type
    }

    // Determine final texture format
    final_format: Texture_Format
    switch target_channels {
    case .Grey:       final_format = .R8_Unorm
    case .Grey_Alpha: final_format = .Rg8_Unorm
    case .Rgb:        final_format = .Rgba8_Unorm
    case .Rgb_Alpha:  final_format = .Rgba8_Unorm
    case .Default:    unreachable()
    }

    pixels: []u8

    // Convert pixel data if needed
    if target_channels == src_channel_type {
        // Direct copy
        size := calculate_image_byte_size(width, height, target_channels)
        pixels = make([]u8, size, allocator)
        src_data := bytes.buffer_to_bytes(&core_img.pixels)
        copy(pixels, src_data)
    } else {
        // Need conversion
        pixels = _convert_pixel_format(core_img, target_channels, allocator) or_return
    }

    img.pixels = pixels
    img.size = { width, height }
    img.format = final_format
    img.channels = target_channels
    img.allocator = allocator

    return img, true
}

@(private)
_convert_pixel_format :: proc(
    img: ^image.Image,
    target_channels: Image_Channel,
    allocator: mem.Allocator,
) -> (pixels: []u8, ok: bool) {
    width := u32(img.width)
    height := u32(img.height)
    src_channels := img.channels
    dst_channels := int(target_channels)

    byte_size := calculate_image_byte_size(width, height, target_channels)
    pixels = make([]u8, byte_size, allocator)

    src_data := bytes.buffer_to_bytes(&img.pixels)

    // Convert pixel by pixel
    for y in 0..<height {
        for x in 0..<width {
            src_idx := int(y * width + x) * src_channels
            dst_idx := int(y * width + x) * dst_channels

            // Read source pixel
            r, g, b, a: u8
            switch src_channels {
            case 1:
                r = src_data[src_idx]
                g, b, a = r, r, 255
            case 2:
                r = src_data[src_idx]
                g, b = r, r
                a = src_data[src_idx + 1]
            case 3:
                r = src_data[src_idx]
                g = src_data[src_idx + 1]
                b = src_data[src_idx + 2]
                a = 255
            case 4:
                r = src_data[src_idx]
                g = src_data[src_idx + 1]
                b = src_data[src_idx + 2]
                a = src_data[src_idx + 3]
            }

            // Write destination pixel
            switch target_channels {
            case .Grey:
                // Convert to grayscale using luminosity method
                grey := u8(0.299 * f32(r) + 0.587 * f32(g) + 0.114 * f32(b) + 0.5)
                pixels[dst_idx] = grey
            case .Grey_Alpha:
                grey := u8(0.299 * f32(r) + 0.587 * f32(g) + 0.114 * f32(b) + 0.5)
                pixels[dst_idx] = grey
                pixels[dst_idx + 1] = a
            case .Rgb:
                pixels[dst_idx] = r
                pixels[dst_idx + 1] = g
                pixels[dst_idx + 2] = b
            case .Rgb_Alpha:
                pixels[dst_idx] = r
                pixels[dst_idx + 1] = g
                pixels[dst_idx + 2] = b
                pixels[dst_idx + 3] = a
            case .Default:
                unreachable()
            }
        }
    }

    return pixels, true
}
