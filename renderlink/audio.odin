#+build !js
package renderlink

// Core
import "base:runtime"
import "core:bytes"
import "core:c"
import "core:io"
import "core:log"
import "core:math"
import "core:mem"
import "core:sync"
import "core:time"
import sa "core:container/small_array"
import os "core:os/os2"

// Vendor
import ma "vendor:miniaudio"

Audio_Context :: struct {
    // Initialization
    ma_context:         ma.context_type,
    ma_log:             ma.log,
    playback_device:    ma.device,
    ma_engine:          ma.engine,
    device_list:        []Audio_Device,
    current:            Audio_Selection,
    notification:       Audio_Notification,
    listener:           Audio_Listener,
    reading_data_mutex: sync.Mutex,

    // Resources
    resources:          Audio_Resource_List,
    resource_mutex:     sync.Mutex,
    sounds:             Pool(Sound_Impl),
    buffers:            Pool(Sound_Buffer_Impl),

    // Internal
    allocator:          mem.Allocator,
    custom_ctx:         runtime.Context,
    initialized:        bool,
}

Audio_Device :: struct {
    name:       string,
    name_buf:   String_Buffer_Small,
    id:         ma.device_id,
    is_default: bool,
}

Audio_Selection :: struct {
    selection: String_Buffer_Small,
    use_null:  bool,
}

Audio_Notification_Type :: enum {
    STARTED,
    STOPPED,
    REROUTED,
    INTERRUPTION_BEGAN,
    INTERRUPTION_ENDED,
    UNLOCKED,
}

Audio_Notification_Callback :: #type proc "contextless" (notification: Audio_Notification_Type)

Audio_Notification :: struct {
    mutex:    sync.Mutex,
    callback: Audio_Notification_Callback,
}

Audio_Listener_Cone :: struct {
    inner_angle: Angle,
    outer_angle: Angle,
    outer_gain:  f32,
}

Audio_Listener :: struct {
    volume:    f32,
    position:  Vec3f,
    direction: Vec3f,
    velocity:  Vec3f,
    up_vector: Vec3f,
    cone:      Audio_Listener_Cone,
}

DEFAULT_AUDIO_LISTENER := Audio_Listener {
    volume    = 100.0,
    position  = { 0.0, 0.0, 0.0 },
    direction = { 0.0, 0.0, -1.0 },
    velocity  = { 0.0, 0.0, 0.0 },
    up_vector = { 0.0, 1.0, 0.0 },
    cone      = { angle_from_degrees(360.0), angle_from_degrees(360.0), 1.0 },
}

Audio_Resource_Proc :: #type proc(resource: rawptr)

Audio_Resource :: struct {
    resource:          rawptr,
    deinitialize_proc: Audio_Resource_Proc,
    reinitialize_proc: Audio_Resource_Proc,
}

Audio_Resource_Handle :: int

Audio_Resource_List :: [dynamic]Audio_Resource

Sound_Map :: map[Sound]struct {}

/*
The type of sound samples.
*/
Sound_Sample :: distinct i16

/*
Storage for audio samples defining a sound.
*/
Sound_Buffer_Impl :: struct {
    // Context
    audio_ctx: ^Audio_Context,

    // Sound buffer data
    samples:   []Sound_Sample,
    info:      Sound_Info,
    duration:  time.Duration, // in seconds
    sounds:    Sound_Map,
    allocator: mem.Allocator,
}

Sound_Buffer :: distinct Handle

/*
Sound source states.
*/
Sound_Status :: enum {
    Stopped,
    Paused,
    Playing,
}

/*
Regular sound that can be played in the audio environment.
*/
Sound_Impl :: struct {
    // This is the struct that makes our object a miniaudio data source,
    // miniaudio expects to find base data here (offset 0, must be first member)
    data_source_base: ma.data_source_base,

    // Context
    audio_ctx:        ^Audio_Context,

    // Sound data
    buffer:           Sound_Buffer,
    cursor:           uint,
    status:           Sound_Status,
    sound:            ma.sound,
    vtable:           ma.data_source_vtable,
    looping:          bool,
    buffer_owned:     bool, // does the sound buffer owned by this sound?
}

Sound :: distinct Handle // Sound handle

/*
Types of sound channels that can be read/written from sound buffers/files.
*/
Sound_Channel :: enum {
    Unspecified,
    Mono,
    Front_Left,
    Front_Right,
    Front_Center,
    Front_Left_Of_Center,
    Front_Right_Of_Center,
    Low_Frequency_Effects,
    Back_Left,
    Back_Right,
    Back_Center,
    Side_Left,
    Side_Right,
    Top_Center,
    Top_Front_Left,
    Top_Front_Right,
    Top_Front_Center,
    Top_Back_Left,
    Top_Back_Right,
    Top_Back_Center,
}

/*
Map of position in sample frame to sound channel.
*/
Sound_Channel_Map :: sa.Small_Array(len(Sound_Channel), Sound_Channel)

Sound_Info :: struct {
    sample_count:  u64,
    sample_rate:   u32,
    channel_count: u32, // len of channel_map
    channel_map:   Sound_Channel_Map,
}

IAudio_Decoder :: struct {
    read:  #type proc "c" (self: Audio_Decoder, samples: rawptr, frame_count: u64) -> u64,
    seek:  #type proc "c" (self: Audio_Decoder, frame_offset: u64),
    close: #type proc "c" (self: Audio_Decoder),
    tell:  #type proc "c" (self: Audio_Decoder) -> i64,
}

IAudio_Decoder_WAV :: struct {
    decoder:       ma.decoder,
    sample_offset: u64,
    using audio:   IAudio_Decoder,
}

Audio_Decoder :: union {
    IAudio_Decoder_WAV,
}

Encoding_Format :: enum i32 {
    Unknown = 0,
    Wav,
    Flac,
    Mp3,
    Vorbis,
    Ogg,
}

/*
Provide read access to sound files.
*/
Sound_Reader :: struct {
    file:   ^os.File,
    memory: struct {
        data:   []byte,
        cursor: uint,
    },
    stream:  io.Stream,
    decoder: Audio_Decoder,
    format:  Encoding_Format,
    info:    Sound_Info,
    ctx:     runtime.Context, // for use outside of Odin calling convention
}

init_audio_context :: proc(self: ^Audio_Context, allocator := context.allocator) -> (ok: bool) {
    assert(self != nil, "Invalid audio context")

    if self.initialized {
        log.warn("Audio context already initialized, skipping...")
        return true
    }

    self.allocator = allocator
    self.custom_ctx = context
    context.allocator = self.allocator

    when ODIN_DEBUG {
        log_callback :: proc "c" (pUserData: rawptr, level: u32, pMessage: cstring) {
            ctx := cast(^Audio_Context)pUserData
            context = ctx.custom_ctx
            if level <= u32(ma.log_level.LOG_LEVEL_WARNING) {
                log.warnf("[miniaudio] %s: %s", ma.log_level_to_string(level), pMessage)
            }
        }

        if self.initialized == false {
            if res := ma.log_init(nil, &self.ma_log); res != .SUCCESS {
                log.errorf("Failed to initialize the audio log: %s", ma.result_description(res))
                return
            }

            if res := ma.log_register_callback(
                &self.ma_log,
                { onLog = log_callback, pUserData = self },
            ); res != .SUCCESS {
                log.errorf("Failed to register audio log callback: %s", ma.result_description(res))
                return
            }
        }
        defer if !ok && self.initialized == false do ma.log_uninit(&self.ma_log)
    }

    ta := context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    // Initialize context with backend selection
    context_config := ma.context_config_init()
    context_config.pLog = &self.ma_log
    device_count: u32
    null_backend := ma.backend.null

    backend_list: sa.Small_Array(2, ^ma.backend)

    // Build backend priority list
    sa.push_back(&backend_list, nil) // Try hardware first
    sa.push_back(&backend_list, &null_backend) // Fallback to null

    backend_list_slice := sa.slice(&backend_list)
    for backend, i in backend_list_slice {
        // Initialize context with current backend
        if res := ma.context_init(backend, 1, &context_config, &self.ma_context); res != .SUCCESS {
            log.errorf("Failed to initialize audio context with backend %v: %s",
                backend, ma.result_description(res))
            if i == sa.len(backend_list) - 1 { // Last backend failed
                return
            }
            continue
        }

        // Check for available devices
        if res := ma.context_get_devices(
            &self.ma_context,
            nil,
            &device_count,
            nil,
            nil,
        ); res != .SUCCESS {
            log.errorf("Failed to enumerate audio devices: %s", ma.result_description(res))
            ma.context_uninit(&self.ma_context)
            if i == sa.len(backend_list) - 1 {
                return
            }
            continue
        }

        // Success if we found devices
        if device_count > 0 {
            break
        }

        // No devices with this backend
        if backend == nil {
            log.warn("No audio playback devices available on hardware")
        }
        ma.context_uninit(&self.ma_context)

        // If this was the last backend, fail
        if i == sa.len(backend_list) - 1 {
            return
        }
    }

    // Warn if we ended up with null backend when hardware was preferred
    if self.ma_context.backend == .null {
        log.warn("Using NULL audio backend despite hardware being preferred")
    }

    get_devices_from_context :: proc(
        ma_context: ^ma.context_type,
        temp_allocator: mem.Allocator,
    ) -> []Audio_Device {
        device_infos: [^]ma.device_info
        device_count: u32

        if res := ma.context_get_devices(ma_context, &device_infos, &device_count, nil, nil);
           res != .SUCCESS {
            log.errorf("Failed to get audio playback devices: %s", ma.result_description(res))
            return {}
        }

        if device_count == 0 do return {}

        // Reserve the first entry for the default device
        device_list := make([dynamic]Audio_Device, 1, temp_allocator)

        device_infos_slice := device_infos[:device_count]

        for &d in device_infos_slice {
            entry := Audio_Device {
                id         = d.id,
                is_default = bool(d.isDefault),
            }

            string_buffer_init(&entry.name_buf, string(cstring(&d.name[0])))

            // The first entry is always the default device
            if entry.is_default || device_count == 1 {
                device_list[0] = entry
            } else {
                append(&device_list, entry)
            }
        }

        return device_list[:]
    }

    retry: bool
    retry_backend: ^ma.backend
    ma_context: ma.context_type

    if res := ma.context_init(nil, 0, nil, &ma_context); res != .SUCCESS {
        log.errorf(
            "Failed to initialize the audio playback context: %s",
            ma.result_description(res),
        )
        return {}
    }
    tmp_device_list := get_devices_from_context(&ma_context, ta)
    if len(tmp_device_list) == 0 && ma_context.backend != .null {
        // Retry with null backend
        retry = true
        retry_backend = &null_backend
    }
    ma.context_uninit(&ma_context)

    if retry {
        // Construct a temporary context using the selected backend to retry
        if res := ma.context_init(retry_backend, 1, nil, &ma_context); res != .SUCCESS {
            log.errorf(
                "Failed to initialize the audio playback context: %s",
                ma.result_description(res),
            )
            return {}
        }
        defer ma.context_uninit(&ma_context)
        retry_device_list := get_devices_from_context(&ma_context, ta)
        if len(retry_device_list) > 0 {
            tmp_device_list = retry_device_list
        }
    }

    if len(tmp_device_list) == 0 do return

    self.device_list = make([]Audio_Device, len(tmp_device_list), allocator)
    default_device: ^Audio_Device

    for &device, i in tmp_device_list {
        entry := &self.device_list[i]
        entry.id = device.id
        entry.is_default = device.is_default
        copy(entry.name_buf.data[:], device.name_buf.data[:])
        entry.name_buf.length = device.name_buf.length
        entry.name = string_buffer_get_string(&entry.name_buf)

        if entry.is_default {
            default_device = entry
        }
    }

    assert(default_device != nil)

    audio_context_data_callback :: proc "c" (
        pDevice: ^ma.device,
        pOutput, pInput: rawptr,
        frameCount: u32,
    ) {
        ctx := cast(^Audio_Context)pDevice.pUserData
        // TODO(Capati): Use atomic operations or proper synchronization instead of sync.guard
        sync.guard(&ctx.reading_data_mutex)
        if res := ma.engine_read_pcm_frames(
            &ctx.ma_engine,
            pOutput,
            u64(frameCount),
            nil,
        ); res != .SUCCESS {
            when ODIN_DEBUG {
                context = ctx.custom_ctx
                log.errorf("Failed to read PCM frames: %s", ma.result_description(res))
            }
        }
    }

    audio_context_notification_callback :: proc "c" (pNotification: ^ma.device_notification) {
        ctx := cast(^Audio_Context)pNotification.pDevice.pUserData

        sync.guard(&ctx.notification.mutex)

        callback := ctx.notification.callback
        if callback == nil do return

        notification_type: Audio_Notification_Type
        switch pNotification.type {
        case .started:             notification_type = .STARTED
        case .stopped:             notification_type = .STOPPED
        case .rerouted:            notification_type = .REROUTED
        case .interruption_began:  notification_type = .INTERRUPTION_BEGAN
        case .interruption_ended:  notification_type = .INTERRUPTION_ENDED
        case .unlocked:            notification_type = .UNLOCKED
        case: return // Unknown notification type
        }

        callback(notification_type)
    }

    // Initialize playback device
    playback_device_config := ma.device_config_init(.playback)
    playback_device_config.dataCallback = audio_context_data_callback
    playback_device_config.notificationCallback = audio_context_notification_callback
    playback_device_config.pUserData = self
    playback_device_config.playback.pDeviceID = &default_device.id

    select_optimal_audio_format :: proc(
        ma_context: ^ma.context_type,
        device_id: ^ma.device_id,
    ) -> ma.format {
        // Test formats in order of preference
        preferred_formats := []ma.format{.f32, .s16, .s24, .s32}

        for format in preferred_formats {
            // Create a test device config
            test_config := ma.device_config_init(.playback)
            test_config.playback.format = format
            test_config.playback.pDeviceID = device_id

            // Test if this format is supported
            test_device: ma.device
            if ma.device_init(ma_context, &test_config, &test_device) == .SUCCESS {
                actual_format := test_device.playback.playback_format
                ma.device_uninit(&test_device)
                return actual_format
            }
        }

        log.warn("No preferred audio format supported, falling back to default")
        return .unknown // Let miniaudio choose
    }

    playback_device_config.playback.format =
        select_optimal_audio_format(&self.ma_context, &default_device.id)

    if res := ma.device_init(
        &self.ma_context,
        &playback_device_config,
        &self.playback_device,
    ); res != .SUCCESS {
        log.errorf("Failed to initialize playback device: %s", ma.result_description(res))
        return
    }

    // Initialize engine
    engine_config := ma.engine_config_init()
    engine_config.pContext = &self.ma_context
    engine_config.pDevice = &self.playback_device
    engine_config.listenerCount = 1

    if res := ma.engine_init(&engine_config, &self.ma_engine); res != .SUCCESS {
        log.errorf("Failed to initialize audio engine: %s", ma.result_description(res))
        return
    }

    // Configure listener and volume
    self.listener = DEFAULT_AUDIO_LISTENER

    engine_device := ma.engine_get_device(&self.ma_engine)
    if engine_device == nil {
        log.error("Failed to get engine device")
        return
    }

    // Set master volume
    normalized_volume := audio_normalize_volume(self.listener.volume)
    if res := ma.device_set_master_volume(engine_device, normalized_volume); res != .SUCCESS {
        log.errorf("Failed to set master volume: %s", ma.result_description(res))
        return
    }

    // Configure listener properties
    ma.engine_listener_set_position(&self.ma_engine, 0,
        self.listener.position.x, self.listener.position.y, self.listener.position.z)

    ma.engine_listener_set_velocity(&self.ma_engine, 0,
        self.listener.velocity.x, self.listener.velocity.y, self.listener.velocity.z)

    ma.engine_listener_set_cone(&self.ma_engine, 0,
        self.listener.cone.inner_angle,
        self.listener.cone.outer_angle,
        self.listener.cone.outer_gain,
    )

    ma.engine_listener_set_world_up(&self.ma_engine, 0,
        self.listener.up_vector.x, self.listener.up_vector.y, self.listener.up_vector.z)

    // Initialize resources
    self.resources = make([dynamic]Audio_Resource)
    pool_init(&self.sounds)
    pool_init(&self.buffers)

    self.initialized = true

    return true
}

audio_context_destroy :: proc(self: ^Audio_Context) {
    assert(self != nil, "Invalid audio context")
    assert(self.initialized, "Audio context not initialized!")

    context.allocator = self.allocator

    if self.buffers.num_objects > 0 {
        log.warnf("Leaked %d sound buffers(s)", self.buffers.num_objects)
    }
    pool_destroy(&self.buffers)

    if self.sounds.num_objects > 0 {
        log.warnf("Leaked %d sounds(s)", self.sounds.num_objects)
    }
    pool_destroy(&self.sounds)

    delete(self.resources)

    // Cleanup miniaudio resources
    ma.engine_stop(&self.ma_engine)
    ma.engine_uninit(&self.ma_engine)
    ma.device_uninit(&self.playback_device)
    ma.context_uninit(&self.ma_context)
    when ODIN_DEBUG {
        ma.log_uninit(&self.ma_log)
    }

    delete(self.device_list)

    self.initialized = false
}

audio_normalize_volume :: proc(volume: f32, min_db: f32 = -60.0, max_db: f32 = 0.0) -> f32 {
    clamped := clamp(volume, 0.0, 100.0)
    if clamped == 0.0 do return 0.0
    // Convert to logarithmic scale for more natural volume perception
    db := min_db + (clamped / 100.0) * (max_db - min_db)
    return math.pow(10.0, db / 20.0)
}

// Change the global volume of all the sounds and musics.
audio_set_global_volume :: proc(ctx: ^Context, volume: f32) {
    // Store the volume in case no audio device exists yet
    ctx.audio_ctx.listener.volume = volume

    if !audio_check_context(&ctx.audio_ctx) do return

    if res := ma.device_set_master_volume(
        ma.engine_get_device(&ctx.audio_ctx.ma_engine),
        audio_normalize_volume(volume),
    ); res != .SUCCESS {
        log.errorf("Failed to set audio device master volume: %s", ma.result_description(res))
    }
}

// Get the current value of the global volume.
audio_get_global_volume :: proc(ctx: ^Context) -> f32 {
    return ctx.audio_ctx.listener.volume
}

// Check if audio context is initialized.
audio_check_context :: #force_inline proc(self: ^Audio_Context) -> bool {
    return self.initialized
}

// Load the sound buffer from a file.
sound_buffer_load_from_file :: proc(
    ctx: ^Context,
    filename: string,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    handle: Sound_Buffer,
    ok: bool,
) #optional_ok {
    reader: Sound_Reader
    sound_reader_load_from_file(ctx, &reader, filename, loc) or_return
    defer sound_reader_close(&reader)

    handle = Sound_Buffer(from_handle(pool_create(&ctx.audio_ctx.buffers, Sound_Buffer_Impl{})))
    buffer := pool_get(&ctx.audio_ctx.buffers, to_handle(handle))

    buffer.allocator = allocator
    buffer.info = reader.info

    _sound_buffer_load(buffer, &reader, loc) or_return

    return handle, true
}

// Load the sound buffer.
sound_buffer_load :: proc {
    sound_buffer_load_from_file,
    // sound_buffer_load_from_memory,
}

// Destroy the sound buffer resources.
sound_buffer_destroy :: proc(ctx: ^Context, buffer: Sound_Buffer, loc := #caller_location) {
    impl := _sound_buffer_get_impl(&ctx.audio_ctx, buffer, loc)
    context.allocator = impl.allocator
    delete(impl.samples)
    pool_remove(&ctx.audio_ctx.buffers, to_handle(buffer))
    // delete(self.sounds)
}

// Open a sound file from the disk for reading.
//
// Inputs:
// - reader: A pointer to a sound reader struct
// - filename:
sound_reader_load_from_file :: proc(
    ctx: ^Context,
    reader: ^Sound_Reader,
    filename: string,
    loc := #caller_location,
) -> (
    ok: bool,
) {
    assert(reader != nil, "Invalid sound buffer", loc)

    // Close any existing file/decoder
    if reader.file != nil {
        sound_reader_close(reader, loc)
    }

    fd, open_err := os.open(filename, {.Read})
    if open_err != nil {
        log.errorf("Failed to open sound file from file: %v", open_err)
        return
    }

    reader.ctx = ctx.audio_ctx.custom_ctx // for use outside of odin calling convention
    reader.file = fd
    reader.stream = os.to_stream(reader.file)
    reader.format = _sound_reader_get_encoding_format(filename)

    #partial switch reader.format {
    case .Wav: _Audio_Decoder_WAV(reader) or_return
    case:
        panic("Unsupported audio format", loc)
    }

    return true
}

sound_reader_close :: proc(self: ^Sound_Reader, loc := #caller_location) {
    assert(self != nil, "Invalid sound reader", loc)

    if self.decoder != nil {
        #partial switch self.format {
        case .Wav:
            decoder := self.decoder.(IAudio_Decoder_WAV)
            decoder->close()
        case:
        }
    }

    if self.file != nil {
        os.close(self.file)
    }
}

// Create a sound from a buffer.
sound_create :: proc(
    ctx: ^Context,
    buffer: Sound_Buffer,
    loc := #caller_location,
) -> (
    sound: Sound,
    ok: bool,
) #optional_ok {
    assert(_sound_buffer_is_valid(buffer), "Invalid sound buffer", loc)

    sound_handle := pool_create(&ctx.audio_ctx.sounds, Sound_Impl{
        audio_ctx = &ctx.audio_ctx,
        buffer    = buffer,
        cursor    = 0,
        looping   = false,
        status    = .Stopped,
    })

    sound = Sound(from_handle(sound_handle))

    impl := _sound_get_impl(&ctx.audio_ctx, sound, loc)

    // Initialize the vtable with proper procedure pointers
    impl.vtable = {
        onRead          = _sound_on_read,
        onSeek          = _sound_on_seek,
        onGetDataFormat = _sound_on_get_data_format,
        onGetCursor     = _sound_on_get_cursor,
        onGetLength     = _sound_on_get_length,
        onSetLooping    = _sound_on_set_looping,
    }

    // Initialize the data source base
    data_source_config := ma.data_source_config_init()
    data_source_config.vtable = &impl.vtable

    if res := ma.data_source_init(
        &data_source_config,
        cast(^ma.data_source)&impl.data_source_base,
    ); res != .SUCCESS {
        log.errorf("Failed to initialize audio data source: %s", ma.result_description(res))
        return
    }

    // Initialize the sound with the data source
    sound_config := ma.sound_config_init_2(&ctx.audio_ctx.ma_engine)
    sound_config.pDataSource = cast(^ma.data_source)&impl.data_source_base
    sound_config.pEndCallbackUserData = impl
    sound_config.endCallback = _sound_on_end

    if res := ma.sound_init_ex(&ctx.audio_ctx.ma_engine, &sound_config, &impl.sound); res != .SUCCESS {
        log.errorf("Failed to initialize sound: %s", ma.result_description(res))
        ma.data_source_uninit(cast(^ma.data_source)&impl.data_source_base)
        return
    }

    return sound, true
}

/*
Load the sound from a file.

Inputs:

- `filename`:  Path of the sound file to load
- `allocator`: The allocator to use for the sound buffer samples (default is `context.allocator`)
- `loc`:       The caller location for debugging purposes (default: `#caller_location`)
*/
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
    buffer := sound_buffer_load_from_file(ctx, filename, allocator, loc) or_return
    sound = sound_create(ctx, buffer, loc) or_return
    impl := _sound_get_impl(&ctx.audio_ctx, sound, loc)
    impl.buffer_owned = true
    return sound, true
}

sound_load :: proc {
    sound_load_from_file,
    // sound_load_from_memory,
}

// Start or resume playing the sound.
sound_play :: proc(ctx: ^Context, sound: Sound, loc := #caller_location) {
    impl := _sound_get_impl(&ctx.audio_ctx, sound, loc)
    if res := ma.sound_start(&impl.sound); res != .SUCCESS {
        log.errorf("Failed to start sound: %s", ma.result_description(res))
    } else {
        impl.status = .Playing
    }
}


// Stop playing the sound.
sound_stop :: proc(ctx: ^Context, sound: Sound, loc := #caller_location) {
    impl := _sound_get_impl(&ctx.audio_ctx, sound, loc)
    if res := ma.sound_stop(&impl.sound); res != .SUCCESS {
        log.errorf("Failed to stop playing sound: %s", ma.result_description(res))
    } else {
        sound_set_playing_offset(ctx, sound, 0)
        impl.status = .Stopped
        audio_wait_for_reading_complete(ctx)
    }
}

// Change the current playing position of the sound.
//
// Inputs:
//
// - `duration_offset`: New playing position, from the beginning of the sound
sound_set_playing_offset :: proc(
    ctx: ^Context,
    sound: Sound,
    duration_offset: time.Duration,
    loc := #caller_location,
) {
    impl := _sound_get_impl(&ctx.audio_ctx, sound, loc)

    if impl.sound.pDataSource == nil || impl.sound.engineNode.pEngine == nil {
        log.error("Sound not properly initialized")
        return
    }

    assert(duration_offset >= 0, "duration_offset cannot be negative")

    frame_index := _ma_sound_get_frame_index(&impl.sound, duration_offset)

    // Update internal cursor to match the seek position
    impl_buffer := _sound_buffer_get_impl(&ctx.audio_ctx, impl.buffer, loc)
    impl.cursor = uint(frame_index * u64(impl_buffer.info.channel_count))
}

// Wait for device reading to complete.
audio_wait_for_reading_complete :: proc(ctx: ^Context) {
    // Once we can lock the reading mutex it means the engine read cycle has been completed
    sync.guard(&ctx.audio_ctx.reading_data_mutex)
}

// Destroy the sound resources.
sound_destroy :: proc(ctx: ^Context, sound: Sound, loc := #caller_location) {
    sound_stop(ctx, sound, loc)
    impl := _sound_get_impl(&ctx.audio_ctx, sound, loc)
    // Uninitialize sound before destroying buffer
    ma.sound_uninit(&impl.sound)
    if impl.buffer_owned {
        sound_buffer_destroy(ctx, impl.buffer, loc)
    }
    pool_remove(&ctx.audio_ctx.sounds, to_handle(sound))
}

// -----------------------------------------------------------------------------
// @(private) impl
// -----------------------------------------------------------------------------

@(private)
_sound_get_impl :: proc "contextless" (
    ctx: ^Audio_Context,
    sound: Sound,
    loc := #caller_location,
) -> ^Sound_Impl {
    assert_contextless(_sound_is_valid(sound), "Invalid sound handle", loc)
    return pool_get(&ctx.sounds, to_handle(sound))
}

@(private)
_sound_buffer_get_impl :: proc "contextless" (
    ctx: ^Audio_Context,
    buffer: Sound_Buffer,
    loc := #caller_location,
) -> ^Sound_Buffer_Impl {
    assert_contextless(_sound_buffer_is_valid(buffer), "Invalid sound buffer handle", loc)
    return pool_get(&ctx.buffers, to_handle(buffer), loc)
}

@(private)
_sound_buffer_load :: #force_inline proc "c" (
    self: ^Sound_Buffer_Impl,
    reader: ^Sound_Reader,
    loc := #caller_location,
) -> (
    ok: bool,
) {
    // Ensure we're using the reader's context
    context = reader.ctx

    sample_count := self.info.sample_count
    self.samples = make([]Sound_Sample, sample_count, self.allocator)
    sample_count_read: u64

    #partial switch reader.format {
    case .Wav:
        decoder := reader.decoder.(IAudio_Decoder_WAV)
        sample_count_read = decoder->read(raw_data(self.samples[:]), sample_count)
    case:
        panic("Unsupported audio format", loc)
    }

    ensure(sample_count_read == sample_count)

    if !_sound_buffer_update(self) {
        log.error("Failed to initialize sound buffer (internal update failure)")
        return false
    }

    return true
}

@(private)
_sound_buffer_update :: proc(self: ^Sound_Buffer_Impl) -> bool {
    if self.info.channel_count == 0 ||
       self.info.sample_rate == 0 ||
       u32(sa.len(self.info.channel_map)) != self.info.channel_count {
        return false
    }

    // Calculate duration
    seconds := f64(len(self.samples)) / f64(self.info.sample_rate) / f64(self.info.channel_count)
    self.duration = time.Duration(seconds * f64(time.Second))

    return true
}

@(private)
_sound_on_end :: proc "c" (user_data: rawptr, pSound: ^ma.sound) {
    impl := cast(^Sound_Impl)user_data
    if impl == nil do return

    impl.status = .Stopped

    if res := ma.sound_seek_to_pcm_frame(pSound, 0); res != .SUCCESS {
        context = runtime.default_context()
        log.errorf("Failed to seek sound to frame 0: %s", ma.result_description(res))
    }
}

@(private)
_sound_on_read :: proc "c" (
    pDataSource: ^ma.data_source,
    pFramesOut: rawptr,
    frameCount: u64,
    pFramesRead: ^u64,
) -> ma.result {
    impl := cast(^Sound_Impl)pDataSource
    if impl == nil do return .INVALID_ARGS

    if !_sound_buffer_is_valid(impl.buffer) do return .NO_DATA_AVAILABLE

    buffer := _sound_buffer_get_impl(impl.audio_ctx, impl.buffer)
    info := buffer.info

    if impl.cursor >= uint(info.sample_count) {
        return .AT_END // No more samples to read
    }

    // Determine how many frames we can read
    if pFramesRead != nil {
        pFramesRead^ = min(
            frameCount,
            (info.sample_count - u64(impl.cursor)) / u64(info.channel_count),
        )
    }

    // Copy the samples to the output
    sample_count := pFramesRead^ * u64(info.channel_count)

    #no_bounds_check {
        mem.copy_non_overlapping(
            pFramesOut,
            &buffer.samples[impl.cursor],
            int(sample_count) * size_of(buffer.samples[0]),
        )
    }

    impl.cursor += uint(sample_count)

    // If we are looping and at the end of the sound, set the cursor back to the start
    if impl.looping && (u64(impl.cursor) >= info.sample_count) {
        impl.cursor = 0
    }

    return .SUCCESS
}

@(private)
_sound_on_seek :: proc "c" (pDataSource: ^ma.data_source, frameIndex: u64) -> ma.result {
    impl := cast(^Sound_Impl)pDataSource
    if impl == nil do return .INVALID_ARGS

    if !_sound_buffer_is_valid(impl.buffer) do return .NO_DATA_AVAILABLE

    buffer := _sound_buffer_get_impl(impl.audio_ctx, impl.buffer)
    impl.cursor = uint(frameIndex * u64(buffer.info.channel_count))

    return .SUCCESS
}

@(private)
_sound_on_get_data_format :: proc "c" (
    pDataSource: ^ma.data_source,
    pFormat: ^ma.format,
    pChannels: ^u32,
    pSampleRate: ^u32,
    pChannelMap: [^]ma.channel,
    channelMapCap: uint,
) -> ma.result {
    impl := cast(^Sound_Impl)pDataSource
    if impl == nil do return .INVALID_ARGS

    if !_sound_buffer_is_valid(impl.buffer) do return .NO_DATA_AVAILABLE

    buffer := _sound_buffer_get_impl(impl.audio_ctx, impl.buffer)
    info := buffer.info

    // Initialize with defaults so sound creation doesn't fail
    if pFormat != nil {
        pFormat^ = .s16
    }
    if pChannels != nil {
        pChannels^ = info.channel_count != 0 ? info.channel_count : 1
    }
    if pSampleRate != nil {
        pSampleRate^ = info.sample_rate != 0 ? info.sample_rate : 44100
    }

    return .SUCCESS
}

@(private)
_sound_on_get_cursor :: proc "c" (pDataSource: ^ma.data_source, pCursor: ^u64) -> ma.result {
    impl := cast(^Sound_Impl)pDataSource
    if impl == nil do return .INVALID_ARGS

    if !_sound_buffer_is_valid(impl.buffer) do return .NO_DATA_AVAILABLE

    buffer := _sound_buffer_get_impl(impl.audio_ctx, impl.buffer)
    if pCursor != nil {
        pCursor^ = u64(impl.cursor / uint(buffer.info.channel_count))
    }

    return .SUCCESS
}

@(private)
_sound_on_get_length :: proc "c" (pDataSource: ^ma.data_source, pLength: ^u64) -> ma.result {
    impl := cast(^Sound_Impl)pDataSource
    if impl == nil do return .INVALID_ARGS

    if !_sound_buffer_is_valid(impl.buffer) do return .NO_DATA_AVAILABLE

    buffer := _sound_buffer_get_impl(impl.audio_ctx, impl.buffer)
    info := buffer.info

    if pLength != nil {
        pLength^ = info.sample_count / u64(info.channel_count)
    }

    return .SUCCESS
}

@(private)
_sound_on_set_looping :: proc "c" (pDataSource: ^ma.data_source, isLooping: b32) -> ma.result {
    impl := cast(^Sound_Impl)pDataSource
    if impl == nil do return .INVALID_ARGS

    impl.looping = bool(isLooping)

    return .SUCCESS
}

@(private)
_sound_buffer_is_valid :: #force_inline proc "contextless" (buffer: Sound_Buffer) -> bool {
    return handle_is_valid(to_handle(buffer))
}

_sound_is_valid :: #force_inline proc "contextless" (sound: Sound) -> bool {
    return handle_is_valid(to_handle(sound))
}

@(private)
_Audio_Decoder_WAV :: proc(reader: ^Sound_Reader) -> (ok: bool) {
    assert(reader != nil, "Invalid sound reader")

    context = reader.ctx

    reader.decoder = IAudio_Decoder_WAV{}
    decoder := &reader.decoder.(IAudio_Decoder_WAV)

    decoder_read :: proc "c" (
        pDecoder: ^ma.decoder,
        pBufferOut: rawptr,
        bytesToRead: c.size_t,
        pBytesRead: ^c.size_t,
    ) -> ma.result {
        if pDecoder == nil || pDecoder.pUserData == nil {
            if pBytesRead != nil do pBytesRead^ = 0
            return .INVALID_ARGS
        }

        reader := cast(^Sound_Reader)pDecoder.pUserData
        context = reader.ctx

        output_bytes := mem.byte_slice(pBufferOut, bytesToRead)
        bytes_read, err := io.read(reader.stream, output_bytes)

        if pBytesRead != nil {
            pBytesRead^ = c.size_t(bytes_read)
        }

        #partial switch err {
        case .None:
            return .SUCCESS
        case .EOF:
            return .AT_END
        case:
            return .IO_ERROR
        }
    }

    decoder_seek :: proc "c" (
        pDecoder: ^ma.decoder,
        byteOffset: i64,
        origin: ma.seek_origin,
    ) -> ma.result {
        if pDecoder == nil || pDecoder.pUserData == nil {
            return .INVALID_ARGS
        }

        reader := cast(^Sound_Reader)pDecoder.pUserData
        context = reader.ctx

        seek_from: io.Seek_From
        #partial switch origin {
        case .start: seek_from = .Start
        case .current: seek_from = .Current
        case .end: seek_from = .End
        case:
            return .INVALID_ARGS
        }

        _, err := io.seek(reader.stream, byteOffset, seek_from)
        if err != .None {
            return .IO_ERROR
        }

        return .SUCCESS
    }

    decoder_tell :: proc "c" (pDecoder: ^ma.decoder, pCursor: ^i64) -> ma.result {
        if pDecoder == nil || pDecoder.pUserData == nil || pCursor == nil {
            return .INVALID_ARGS
        }

        reader := cast(^Sound_Reader)pDecoder.pUserData
        context = reader.ctx

        pos, err := io.seek(reader.stream, 0, .Current)
        if err != .None {
            return .IO_ERROR
        }

        pCursor^ = pos
        return .SUCCESS
    }

    config := ma.decoder_config_init_default()
    config.encodingFormat = .wav
    config.format = .s16

    if res := ma.decoder_init(decoder_read, decoder_seek, reader, &config, &decoder.decoder);
       res != .SUCCESS {
        log.errorf("Failed to initialize decoder: %s", ma.result_description(res))
        return
    }

    available_frames: u64
    if res := ma.decoder_get_available_frames(&decoder.decoder, &available_frames);
       res != .SUCCESS {
        log.errorf("Failed to get available frames from decoder: %s", ma.result_description(res))
        return
    }

    format := ma.format.unknown
    sample_rate: u32
    channel_map: [len(Sound_Channel)]ma.channel

    if res := ma.decoder_get_data_format(
        &decoder.decoder,
        &format,
        &reader.info.channel_count,
        &sample_rate,
        raw_data(channel_map[:]),
        len(channel_map),
    ); res != .SUCCESS {
        log.errorf("Failed to get data format from decoder: %s", ma.result_description(res))
        return
    }

    reader.info.sample_count = available_frames * u64(reader.info.channel_count)
    reader.info.sample_rate = sample_rate

    for i in 0 ..< reader.info.channel_count {
        sound_channel := _ma_channel_to_sound_channel(channel_map[i])
        sa.push(&reader.info.channel_map, sound_channel)
    }

    decoder.read = proc "c" (dec: Audio_Decoder, samples: rawptr, frame_count: u64) -> u64 {
        self := dec.(IAudio_Decoder_WAV)
        reader := cast(^Sound_Reader)self.decoder.pUserData

        context = reader.ctx

        frames_read: u64
        if res := ma.decoder_read_pcm_frames(
            &self.decoder,
            samples,
            frame_count / u64(reader.info.channel_count),
            &frames_read,
        ); res != .SUCCESS {
            log.errorf("Failed to read from sound stream: %s", ma.result_description(res))
            return 0
        }

        return frames_read * u64(reader.info.channel_count)
    }

    decoder.seek = proc "c" (dec: Audio_Decoder, sample_offset: u64) {
        self := dec.(IAudio_Decoder_WAV)
        reader := cast(^Sound_Reader)self.decoder.pUserData

        context = reader.ctx

        if res := ma.decoder_seek_to_pcm_frame(
            &self.decoder,
            sample_offset / u64(reader.info.channel_count),
        ); res != .SUCCESS {
            log.errorf("Failed to seek sound stream: %s", ma.result_description(res))
        }
    }

    decoder.close = proc "c" (dec: Audio_Decoder) {
        self := dec.(IAudio_Decoder_WAV)
        reader := cast(^Sound_Reader)self.decoder.pUserData

        context = reader.ctx

        if res := ma.decoder_uninit(&self.decoder); res != .SUCCESS {
            log.errorf("Failed to uninitialize decoder: %s", ma.result_description(res))
        }
    }

    return true
}

@(private)
_sound_reader_get_encoding_format_from_filename :: proc(
    filename: string,
) -> (
    format: Encoding_Format,
) {
    _, ext := os.split_filename(filename)
    switch ext {
    case "mp3": format  = .Mp3
    case "flac": format = .Flac
    case "wav": format  = .Wav
    case "ogg": format  = .Ogg
    }
    return
}

@(private)
_sound_reader_get_encoding_format_from_stream :: proc(stream: io.Stream) -> Encoding_Format {
    start_pos, _ := io.seek(stream, 0, .Current)
    defer io.seek(stream, start_pos, .Start)

    data: [12]u8
    io.read(stream, data[:])

    // WAV: "RIFF" at start, "WAVE" at offset 8
    if bytes.compare(data[0:4], {'R', 'I', 'F', 'F'}) == 0 &&
       bytes.compare(data[8:12], {'W', 'A', 'V', 'E'}) == 0 {
        return .Wav
    }

    // MP3: ID3 tag or MPEG sync
    if bytes.compare(data[0:3], {'I', 'D', '3'}) == 0 ||
       (data[0] == 0xFF && (data[1] & 0xE0) == 0xE0) {
        return .Mp3
    }

    // FLAC: "fLaC" magic
    if bytes.compare(data[0:4], {'f', 'L', 'a', 'C'}) == 0 {
        return .Flac
    }

    // OGG: "OggS" magic
    if bytes.compare(data[0:4], {'O', 'g', 'g', 'S'}) == 0 {
        return .Ogg
    }

    return .Unknown
}

_sound_reader_get_encoding_format :: proc {
    _sound_reader_get_encoding_format_from_filename,
    _sound_reader_get_encoding_format_from_stream,
}

@(private)
_ma_channel_to_sound_channel :: proc(ma_channel: ma.channel) -> (channel: Sound_Channel) {
    #partial switch ma_channel {
    case .NONE: channel = .Unspecified
    case .MONO: channel = .Mono
    case .FRONT_LEFT: channel = .Front_Left
    case .FRONT_RIGHT: channel = .Front_Right
    case .FRONT_CENTER: channel = .Front_Center
    case .FRONT_LEFT_CENTER: channel = .Front_Left_Of_Center
    case .FRONT_RIGHT_CENTER: channel = .Front_Right_Of_Center
    case .LFE: channel = .Low_Frequency_Effects
    case .BACK_LEFT: channel = .Back_Left
    case .BACK_RIGHT: channel = .Back_Right
    case .BACK_CENTER: channel = .Back_Center
    case .SIDE_LEFT: channel = .Side_Left
    case .SIDE_RIGHT: channel = .Side_Right
    case .TOP_CENTER: channel = .Top_Center
    case .TOP_FRONT_LEFT: channel = .Top_Front_Left
    case .TOP_FRONT_RIGHT: channel = .Top_Front_Right
    case .TOP_FRONT_CENTER: channel = .Top_Front_Center
    case .TOP_BACK_LEFT: channel = .Top_Back_Left
    case .TOP_BACK_RIGHT: channel = .Top_Back_Right
    case:
        assert(ma_channel == .TOP_BACK_CENTER)
        channel = .Top_Back_Center
    }
    return
}

@(private)
_ma_sound_get_frame_index :: proc(
    sound: ^ma.sound,
    duration_offset: time.Duration,
) -> (
    frame_index: u64,
) {
    // Get the sample rate from the sound
    sample_rate: u32
    if res := ma.sound_get_data_format(sound, nil, nil, &sample_rate, nil, 0); res != .SUCCESS {
        log.errorf("Failed to get sound data format 0: %s", ma.result_description(res))
        return
    }

    // Convert duration to frame index
    duration_seconds := time.duration_seconds(duration_offset)
    frame_index = u64(duration_seconds * f64(sample_rate))

    // Perform the actual seek operation
    if res := ma.sound_seek_to_pcm_frame(sound, frame_index); res != .SUCCESS {
        log.errorf(
            "Failed to seek sound to pcm frame %d: %s",
            frame_index,
            ma.result_description(res),
        )
    }

    return
}
