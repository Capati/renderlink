package renderlink

// Local libs
import gpu_shared "../libs/gpu/shared"
import app "../application"

Video_Mode :: app.Video_Mode
App_Init_Callback :: app.App_Init_Callback
App_Draw_Callback :: app.App_Draw_Callback
App_Event_Callback :: app.App_Event_Callback
App_Quit_Callback :: app.App_Quit_Callback
Settings :: app.Settings
Application_Callbacks :: app.Application_Callbacks
Application :: app.Application
Event :: app.Event
Quit_Event :: app.Quit_Event
Resize_Event :: app.Resize_Event
Key_Pressed_Event :: app.Key_Pressed_Event
Key_Released_Event :: app.Key_Released_Event
Mouse_Button_Pressed_Event :: app.Mouse_Button_Pressed_Event
Mouse_Button_Released_Event :: app.Mouse_Button_Released_Event
Mouse_Wheel_Event :: app.Mouse_Wheel_Event
Mouse_Moved_Event :: app.Mouse_Moved_Event
Minimized_Event :: app.Minimized_Event
Restored_Event :: app.Restored_Event

SETTINGS_DEFAULT :: app.SETTINGS_DEFAULT

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

Handle :: gpu_shared.Handle
Internal_Handle :: gpu_shared.Internal_Handle
Pool_Entry :: gpu_shared.Pool_Entry
Pool :: gpu_shared.Pool
from_handle :: gpu_shared.from_handle
to_handle :: gpu_shared.to_handle
handle_from_ptr :: gpu_shared.handle_from_ptr
handle_is_empty :: gpu_shared.handle_is_empty
handle_is_valid :: gpu_shared.handle_is_valid
handle_index :: gpu_shared.handle_index
handle_gen :: gpu_shared.handle_gen
pool_set_defaults :: gpu_shared.pool_set_defaults
pool_init :: gpu_shared.pool_init
pool_create :: gpu_shared.pool_create
pool_get :: gpu_shared.pool_get
pool_get_from_index :: gpu_shared.pool_get_from_index
pool_get_handle :: gpu_shared.pool_get_handle
pool_find_handle :: gpu_shared.pool_find_handle
pool_remove :: gpu_shared.pool_remove
pool_len :: gpu_shared.pool_len
pool_is_empty :: gpu_shared.pool_is_empty
pool_clear :: gpu_shared.pool_clear
pool_destroy :: gpu_shared.pool_destroy

Vec2u :: app.Vec2u
Vec3u :: app.Vec3u
Vec4u :: app.Vec4u
Vec2i :: app.Vec2i
Vec3i :: app.Vec3i
Vec4i :: app.Vec4i
Vec2f :: app.Vec2f
Vec3f :: app.Vec3f
Vec4f :: app.Vec4f

to_bytes :: gpu_shared.to_bytes
