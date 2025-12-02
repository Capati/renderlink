package renderlink

// Local libs
import "../gpu"
import "../shared"

Sized_Buffer :: struct {
    device: gpu.Device,
    buffer: gpu.Buffer,
    size:   gpu.Buffer_Address,
    usage:  gpu.Buffer_Usages,
    label:  shared.String_Buffer_Small,
}

create_buffer :: proc(
    ctx: ^Context,
    label: string,
    #any_int size: gpu.Buffer_Address,
    usage: gpu.Buffer_Usages,
) -> (
    buffer: Sized_Buffer,
) {
    usage := usage

    buffer.buffer = gpu.device_create_buffer(ctx.base.device, {
        label = label,
        usage = usage,
        size = size,
        mapped_at_creation = false,
    })
    assert(buffer.buffer != nil)

    buffer.device = ctx.base.device
    buffer.size = size
    buffer.usage = usage

    if len(label) > 0 {
        shared.string_buffer_init(&buffer.label, label)
    }

    return
}

buffer_destroy :: proc(self: ^Sized_Buffer) {
    assert(self != nil, "Invalid buffer")
    gpu.buffer_release(self.buffer)
}

sized_buffer_copy :: proc(self: ^Sized_Buffer, queue: gpu.Queue, data: []byte) {
    data_len := u64(len(data))

    if data_len > self.size {
        gpu.buffer_release(self.buffer)
        self.buffer = gpu.device_create_buffer(self.device, {
            usage = self.usage,
            size = data_len,
            mapped_at_creation = false,
        })
        self.size = data_len
    }

    // Write to the current buffer (which the GPU isn't using)
    gpu.queue_write_buffer(queue, self.buffer, 0, data)
}
