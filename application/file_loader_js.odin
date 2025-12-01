#+build js
package application

// Core
import "base:runtime"
import "core:mem"
import "core:log"

foreign import "odin_env"

@(default_calling_convention = "contextless")
foreign odin_env {
    load_file_sync :: proc(path: string, buffer: [^]u8, buffer_size: int) -> int ---
}

load_file :: proc(filename: string, allocator := context.allocator) -> (data: []u8, ok: bool) {
    // Create temporary buffer
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore = allocator == context.temp_allocator)
    temp_buffer := make([]u8, 1 * mem.Megabyte, context.temp_allocator)

    // Load file into buffer
    length := load_file_sync(filename, raw_data(temp_buffer), len(temp_buffer))

    if length <= 0 {
        log.errorf("Failed to load file: %s", filename)
        return
    }

    // Copy to final buffer
    data = make([]u8, length, allocator)
    copy(data, temp_buffer[:length])

    return data, true
}
