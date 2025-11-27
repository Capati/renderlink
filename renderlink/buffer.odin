package renderlink

// Local libs
import "../gpu"
import "../shared"

Sized_Buffer :: struct {
    device:        gpu.Device,
    buffers:       [3]gpu.Buffer,  // Triple buffering
    current_index: int,
    size:          gpu.Buffer_Address,
    usage:         gpu.Buffer_Usages,
    label:         shared.String_Buffer_Small,
}

create_buffer :: proc(
    ctx: ^Context,
    label: string,
    size: gpu.Buffer_Address,
    usage: gpu.Buffer_Usages,
) -> (
    buffer: Sized_Buffer,
) {
    usage := usage
    usage += {.Copy_Dst}

    // Create 3 buffers
    for i in 0..<3 {
        buffer.buffers[i] = gpu.device_create_buffer(ctx.base.device, {
            label = label,
            usage = usage,
            size = size,
            mapped_at_creation = false,
        })
        assert(buffer.buffers[i] != nil)
    }

    buffer.device = ctx.base.device
    buffer.size = size
    buffer.usage = usage
    buffer.current_index = 0

    if len(label) > 0 {
        shared.string_buffer_init(&buffer.label, label)
    }
    return
}

buffer_destroy :: proc(self: ^Sized_Buffer) {
    assert(self != nil, "Invalid buffer")
    for i in 0..<3 {
        if self.buffers[i] != nil {
            gpu.buffer_release(self.buffers[i])
        }
    }
}

// Get the current buffer to use for rendering
sized_buffer_get_current :: proc(self: ^Sized_Buffer) -> gpu.Buffer {
    return self.buffers[self.current_index % 3]
}

sized_buffer_copy :: proc(self: ^Sized_Buffer, queue: gpu.Queue, data: []byte) {
    data_len := u64(len(data))

    // Move to next buffer in the ring
    self.current_index += 1
    current_idx := self.current_index % 3

    if data_len > self.size {
        // Need to resize - recreate all buffers
        for i in 0..<3 {
            gpu.buffer_release(self.buffers[i])
            self.buffers[i] = gpu.device_create_buffer(self.device, {
                usage = self.usage,
                size = data_len,
                mapped_at_creation = false,
            })
        }
        self.size = data_len
    }

    // Write to the current buffer (which the GPU isn't using)
    gpu.queue_write_buffer(queue, self.buffers[current_idx], 0, data)
}
