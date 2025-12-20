package application

// Local libs
import gpu_shared "../libs/gpu/shared"

String_Buffer_Small :: gpu_shared.String_Buffer_Small
string_buffer_init :: gpu_shared.string_buffer_init
string_buffer_append :: gpu_shared.string_buffer_append
string_buffer_append_int :: gpu_shared.string_buffer_append_int
string_buffer_append_f64 :: gpu_shared.string_buffer_append_f64
string_buffer_clear :: gpu_shared.string_buffer_clear
string_buffer_capacity :: gpu_shared.string_buffer_capacity
string_buffer_is_full :: gpu_shared.string_buffer_is_full
string_buffer_is_empty :: gpu_shared.string_buffer_is_empty
string_buffer_get_string :: gpu_shared.string_buffer_get_string
string_buffer_get_cstring :: gpu_shared.string_buffer_get_cstring
string_buffer_clone_string :: gpu_shared.string_buffer_clone_string
