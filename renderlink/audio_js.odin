#+build js
package renderlink

Audio_Context :: struct {
}

Sound :: struct {
}

init_audio_context :: proc(self: ^Audio_Context, allocator := context.allocator) -> (ok: bool) {
    return true
}

audio_context_destroy :: proc(self: ^Audio_Context) {
}

@(require_results)
sound_load_from_file :: proc(
    ctx: ^Context,
    filename: string,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    sound: Sound,
    ok: bool,
) #optional_ok {
    return sound, true
}

sound_load :: proc {
    sound_load_from_file,
    // sound_load_from_memory,
}

sound_play :: proc(ctx: ^Context, sound: Sound, loc := #caller_location) {
}

sound_destroy :: proc(ctx: ^Context, sound: Sound, loc := #caller_location) {
}
