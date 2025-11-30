package renderlink

// Local libs
import "../shared"
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

String_Buffer_Small :: shared.String_Buffer_Small
string_buffer_init :: shared.string_buffer_init
string_buffer_append :: shared.string_buffer_append
string_buffer_append_int :: shared.string_buffer_append_int
string_buffer_append_f64 :: shared.string_buffer_append_f64
string_buffer_clear :: shared.string_buffer_clear
string_buffer_capacity :: shared.string_buffer_capacity
string_buffer_is_full :: shared.string_buffer_is_full
string_buffer_is_empty :: shared.string_buffer_is_empty
string_buffer_get_string :: shared.string_buffer_get_string
string_buffer_get_cstring :: shared.string_buffer_get_cstring
string_buffer_clone_string :: shared.string_buffer_clone_string

Handle :: shared.Handle
Internal_Handle :: shared.Internal_Handle
Pool_Entry :: shared.Pool_Entry
Pool :: shared.Pool
from_handle :: shared.from_handle
to_handle :: shared.to_handle
handle_from_ptr :: shared.handle_from_ptr
handle_is_empty :: shared.handle_is_empty
handle_is_valid :: shared.handle_is_valid
handle_index :: shared.handle_index
handle_gen :: shared.handle_gen
pool_set_defaults :: shared.pool_set_defaults
pool_init :: shared.pool_init
pool_create :: shared.pool_create
pool_get :: shared.pool_get
pool_get_from_index :: shared.pool_get_from_index
pool_get_handle :: shared.pool_get_handle
pool_find_handle :: shared.pool_find_handle
pool_remove :: shared.pool_remove
pool_len :: shared.pool_len
pool_is_empty :: shared.pool_is_empty
pool_clear :: shared.pool_clear
pool_destroy :: shared.pool_destroy

Vec2u :: app.Vec2u
Vec3u :: app.Vec3u
Vec4u :: app.Vec4u
Vec2i :: app.Vec2i
Vec3i :: app.Vec3i
Vec4i :: app.Vec4i
Vec2f :: app.Vec2f
Vec3f :: app.Vec3f
Vec4f :: app.Vec4f

to_bytes :: shared.to_bytes
