#+build windows
package application

// // Core
// import "base:runtime"
// import "core:log"
// import win32 "core:sys/windows"

// // Libs
// import "../gpu"

// foreign import user32 "system:User32.lib"

// @(default_calling_convention="system")
// foreign user32 {
//     ChangeDisplaySettingsW :: proc(
//         lpDevMode: ^win32.DEVMODEW, dwFlags: win32.DWORD) -> win32.LONG ---
// }

// Window_Impl :: struct {
//     using _base: Window_Base,
//     instance:    win32.HINSTANCE,
//     hwnd:        win32.HWND,
// }

// @(require_results)
// _window_create :: proc(
//     mode: Video_Mode,
//     title: string,
//     style: Window_Styles,
//     state: Window_State,
//     allocator: runtime.Allocator,
//     loc := #caller_location,
// ) -> Window {
//     impl := new(Window_Impl, allocator)
//     ensure(impl != nil, "Failed to allocate window implementation", loc)

//     impl.custom_context = context
//     impl.allocator = allocator
//     impl.is_fullscreen = state == .Fullscreen
//     impl.mode = mode

//     runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

//     // Set that this process is DPI aware and can handle DPI scaling
//     win32.SetProcessDPIAware()
//     impl.instance = win32.HINSTANCE(win32.GetModuleHandleW(nil))
//     class_name_w := win32.utf8_to_wstring("renderlink", context.temp_allocator)

//     cls := win32.WNDCLASSW {
//         lpfnWndProc   = _win32_window_proc,
//         lpszClassName = class_name_w,
//         hInstance     = impl.instance,
//         hCursor       = win32.LoadCursorA(nil, win32.IDC_ARROW),
//     }

//     ensure(win32.RegisterClassW(&cls) != 0)

//     // Calculate window style based on input flags
//     window_style: win32.DWORD = win32.WS_OVERLAPPEDWINDOW

//     if .Borderless in style {
//         window_style = win32.WS_POPUP
//     }

//     if !(.Resizable in style) && !(.Borderless in style) {
//         window_style &= ~(win32.WS_THICKFRAME | win32.WS_MAXIMIZEBOX)
//     }

//     // Calculate window rect
//     rect := win32.RECT {
//         left   = 0,
//         top    = 0,
//         right  = i32(impl.mode.width),
//         bottom = i32(impl.mode.height),
//     }

//     win32.AdjustWindowRect(&rect, window_style, false)

//     window_width := rect.right - rect.left
//     window_height := rect.bottom - rect.top

//     // Calculate position
//     x, y: i32 = 100, 100
//     if .Centered in style {
//         screen_width := win32.GetSystemMetrics(win32.SM_CXSCREEN)
//         screen_height := win32.GetSystemMetrics(win32.SM_CYSCREEN)
//         x = (screen_width - window_width) / 2
//         y = (screen_height - window_height) / 2
//     }

//     title_w := win32.utf8_to_wstring(title, context.temp_allocator)

//     // Create window
//     impl.hwnd = win32.CreateWindowW(
//         class_name_w,
//         title_w,
//         window_style,
//         x, y,
//         window_width, window_height,
//         nil, nil, impl.instance,
//         cast(rawptr)impl,
//     )
//     assert(impl.hwnd != nil, "Failed creating window")

//     // Store client area dimensions
//     impl.size = { impl.mode.width, impl.mode.height }

//     // Store the impl pointer in the window's user data
//     win32.SetWindowLongPtrW(impl.hwnd, win32.GWLP_USERDATA, cast(win32.LONG_PTR)uintptr(impl))

//     if impl.is_fullscreen {
//         _window_switch_to_fullscreen(Window(impl), impl.mode)
//     }

//     win32.ShowWindow(impl.hwnd, win32.SW_SHOW)
//     win32.UpdateWindow(impl.hwnd)

//     return cast(Window)impl
// }

// _window_destroy :: proc(window: Window) {
//     impl := _win32_get_impl(window)
//     context.allocator = impl.allocator

//     if impl.hwnd != nil {
//         win32.DestroyWindow(impl.hwnd)
//     }

//     free(impl)
// }

// @(require_results)
// _window_get_size :: proc "contextless" (window: Window) -> Vec2u {
//     impl := _win32_get_impl(window)
//     rect: win32.RECT
//     win32.GetClientRect(impl.hwnd, &rect)
//     return { u32(rect.right - rect.left), u32(rect.bottom - rect.top) }
// }

// _window_switch_to_fullscreen :: proc (window: Window, mode: Video_Mode) {
//     impl := _win32_get_impl(window)

//     // TODO: Where is this defined in win32 package? Do we need?
//     DM_PELSWIDTH           :: 0x00080000
//     DM_PELSHEIGHT          :: 0x00100000
//     DM_BITSPERPEL          :: 0x00040000
//     CDS_FULLSCREEN         :: 0x00000004
//     DISP_CHANGE_SUCCESSFUL :: 0

//     win32_mode: win32.DEVMODEW
//     win32_mode.dmSize = size_of(win32.DEVMODEW)
//     win32_mode.dmPelsWidth = mode.width
//     win32_mode.dmPelsHeight = mode.height
//     win32_mode.dmBitsPerPel = mode.bits_per_pixel
//     win32_mode.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_BITSPERPEL

//      // Apply fullscreen mode
//     if ChangeDisplaySettingsW(&win32_mode, CDS_FULLSCREEN) != DISP_CHANGE_SUCCESSFUL {
//         log.error("Failed to change display mode for fullscreen")
//         return
//     }

//     // Make the window flags compatible with fullscreen mode
//     win32.SetWindowLongPtrW(impl.hwnd, win32.GWL_STYLE,
//         win32.LONG_PTR(win32.WS_POPUP) |
//         win32.LONG_PTR(win32.WS_CLIPCHILDREN) |
//         win32.LONG_PTR(win32.WS_CLIPSIBLINGS))
//     win32.SetWindowLongPtrW(impl.hwnd, win32.GWL_EXSTYLE, win32.LONG_PTR(win32.WS_EX_APPWINDOW))

//     // Resize the window so that it fits the entire screen
//     win32.SetWindowPos(
//         impl.hwnd,
//         win32.HWND_TOP,
//         0,
//         0,
//         i32(mode.width),
//         i32(mode.height),
//         win32.SWP_FRAMECHANGED,
//     )
// }

// window_win32_get_instance :: proc(window: Window) -> win32.HINSTANCE {
//     impl := _win32_get_impl(window)
//     return impl.instance
// }

// window_win32_get_hwnd :: proc(window: Window) -> win32.HWND {
//     impl := _win32_get_impl(window)
//     return impl.hwnd
// }

// _window_get_gpu_surface :: proc(
//     window: Window,
//     instance: gpu.Instance,
// ) -> (
//     surface: gpu.Surface,
//     ok: bool,
// ) #optional_ok {
//     impl := _win32_get_impl(window)
//     descriptor := gpu.Surface_Descriptor {
//         target = gpu.Surface_Source_Windows_HWND {
//             hinstance = impl.instance,
//             hwnd = impl.hwnd,
//         },
//     }
//     return gpu.instance_create_surface(instance, descriptor)
// }

// // -----------------------------------------------------------------------------
// // @(private) impl
// // -----------------------------------------------------------------------------

// _window_process_events :: proc "contextless" (window: Window) {
//     // impl := _win32_get_impl(window)
//     msg: win32.MSG
//     for win32.PeekMessageW(&msg, nil, 0, 0, win32.PM_REMOVE) {
//         win32.TranslateMessage(&msg)
//         win32.DispatchMessageW(&msg)
//     }
// }

// _window_filter_event :: proc "contextless" (impl: ^Window_Impl, event: ^Event) {
//     // #partial switch &ev in event {
//     // case Resize_Event:
//     // case Key_Event:
//     // }
// }

// _win32_get_impl_from_hwnd :: #force_inline proc "stdcall" (hwnd: win32.HWND) -> ^Window_Impl {
//     impl := win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA)
//     assert_contextless(impl != 0, "Invalid window handle")
//     return cast(^Window_Impl)uintptr(impl)
// }

// _win32_get_impl :: proc {
//     _window_get_impl,
//     _win32_get_impl_from_hwnd,
// }

// _win32_window_proc :: proc "stdcall" (
//     hwnd: win32.HWND,
//     msg: win32.UINT,
//     wparam: win32.WPARAM,
//     lparam: win32.LPARAM,
// ) -> win32.LRESULT {
//     switch msg {
//     // Destroy event
//     case win32.WM_DESTROY:
//         win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, 0)
//         win32.PostQuitMessage(0)
//         return 0

//     //Set cursor event
//     case win32.WM_SETCURSOR:
//         // The mouse has moved, if the cursor is in our window we must refresh the cursor
//         if (win32.LOWORD(lparam) == win32.HTCLIENT) {
//             // win32.SetCursor(impl.cursor_visible ? impl.last_cursor : nil)
//         }

//     // Close event
//     case win32.WM_CLOSE:
//         dispatch_event(Quit_Event{})
//         return 0

//     // Resize event
//     case win32.WM_SIZE:
//         impl := _win32_get_impl(hwnd)
//         window := Window(impl)
//         curr_size := _window_get_size(window)

//         // Handle minimize/restore events
//         if wparam == win32.SIZE_MINIMIZED {
//             dispatch_event(Minimized_Event{ minimized = true })
//         } else if wparam == win32.SIZE_RESTORED {
//             dispatch_event(Restored_Event{ restored = true })
//         }

//         // Consider only events triggered by a maximize or a un-maximize
//         if wparam != win32.SIZE_MINIMIZED && !impl.is_resizing && impl.size != curr_size {
//             impl.size = curr_size
//             dispatch_event(Resize_Event{ curr_size })
//         }

//         return 0

//     // Start resizing
//     case win32.WM_ENTERSIZEMOVE:
//         impl := _win32_get_impl(hwnd)
//         impl.is_resizing = true
//         return 0

//     // Stop resizing
//     case win32.WM_EXITSIZEMOVE:
//         impl := _win32_get_impl(hwnd)
//         window := Window(impl)
//         impl.is_resizing = false
//         size := _window_get_size(window)
//         if impl.size != size {
//             impl.size = size
//             dispatch_event(Resize_Event{ size })
//         }
//         return 0

//     case win32.WM_KEYDOWN, win32.WM_SYSKEYDOWN:
//         event := Key_Pressed_Event {
//             key      = _win32_keyboard_to_key(wparam, lparam),
//             scancode = _win32_keyboard_to_scancode(wparam, lparam),
//             ctrl     = win32.GetKeyState(win32.VK_CONTROL) < 0,
//             shift    = win32.GetKeyState(win32.VK_SHIFT) < 0,
//             alt      = win32.GetKeyState(win32.VK_MENU) < 0,
//         }
//         dispatch_event(event)
//         return 0

//     case win32.WM_KEYUP, win32.WM_SYSKEYUP:
//         event := Key_Released_Event {
//             key      = _win32_keyboard_to_key(wparam, lparam),
//             scancode = _win32_keyboard_to_scancode(wparam, lparam),
//             ctrl     = win32.GetKeyState(win32.VK_CONTROL) < 0,
//             shift    = win32.GetKeyState(win32.VK_SHIFT) < 0,
//             alt      = win32.GetKeyState(win32.VK_MENU) < 0,
//         }
//         dispatch_event(event)
//         return 0

//     case win32.WM_LBUTTONDOWN:
//         pos := _win32_get_mouse_pos(lparam)
//         event := Mouse_Button_Pressed_Event {
//             button = .Left,
//             pos    = pos,
//         }
//         dispatch_event(event)
//         return 0

//     case win32.WM_LBUTTONUP:
//         pos := _win32_get_mouse_pos(lparam)
//         event := Mouse_Button_Released_Event {
//             button = .Left,
//             pos    = pos,
//         }
//         dispatch_event(event)
//         return 0

//     case win32.WM_RBUTTONDOWN:
//         pos := _win32_get_mouse_pos(lparam)
//         event := Mouse_Button_Pressed_Event {
//             button = .Right,
//             pos    = pos,
//         }
//         dispatch_event(event)
//         return 0

//     case win32.WM_RBUTTONUP:
//         pos := _win32_get_mouse_pos(lparam)
//         event := Mouse_Button_Released_Event {
//             button = .Right,
//             pos    = pos,
//         }
//         dispatch_event(event)
//         return 0

//     case win32.WM_MBUTTONDOWN:
//         pos := _win32_get_mouse_pos(lparam)
//         event := Mouse_Button_Pressed_Event {
//             button = .Middle,
//             pos    = pos,
//         }
//         dispatch_event(event)
//         return 0

//     case win32.WM_MBUTTONUP:
//         pos := _win32_get_mouse_pos(lparam)
//         event := Mouse_Button_Released_Event {
//             button = .Middle,
//             pos    = pos,
//         }
//         dispatch_event(event)
//         return 0

//     case win32.WM_XBUTTONDOWN:
//         pos := _win32_get_mouse_pos(lparam)
//         xbutton := win32.GET_XBUTTON_WPARAM(wparam)
//         button: Mouse_Button = xbutton == win32.XBUTTON1 ? .Four : .Five
//         event := Mouse_Button_Pressed_Event {
//             button = button,
//             pos    = pos,
//         }
//         dispatch_event(event)
//         return 1

//     case win32.WM_XBUTTONUP:
//         pos := _win32_get_mouse_pos(lparam)
//         xbutton := win32.GET_XBUTTON_WPARAM(wparam)
//         button: Mouse_Button = xbutton == win32.XBUTTON1 ? .Four : .Five
//         event := Mouse_Button_Released_Event {
//             button = button,
//             pos    = pos,
//         }
//         dispatch_event(event)
//         return 1

//     case win32.WM_MOUSEMOVE:
//         // impl := _win32_get_impl(hwnd)
//         pos := _win32_get_mouse_pos(lparam)

//         // Determine which button is pressed (if any)
//         button: Mouse_Button = .Unknown
//         action: Input_Action = .None

//         if wparam & win32.MK_LBUTTON != 0 {
//             button = .Left
//             action = .Pressed
//         } else if wparam & win32.MK_RBUTTON != 0 {
//             button = .Right
//             action = .Pressed
//         } else if wparam & win32.MK_MBUTTON != 0 {
//             button = .Middle
//             action = .Pressed
//         } else if wparam & win32.MK_XBUTTON1 != 0 {
//             button = .Four
//             action = .Pressed
//         } else if wparam & win32.MK_XBUTTON2 != 0 {
//             button = .Five
//             action = .Pressed
//         }

//         event := Mouse_Moved_Event {
//             pos    = pos,
//             button = button,
//             action = action,
//         }
//         dispatch_event(event)
//         return 0

//     case win32.WM_MOUSEWHEEL:
//         delta := f32(win32.GET_WHEEL_DELTA_WPARAM(wparam)) / f32(win32.WHEEL_DELTA)
//         event := Mouse_Wheel_Event{ 0, delta }
//         dispatch_event(event)
//         return 0

//     case win32.WM_MOUSEHWHEEL:
//         delta := f32(win32.GET_WHEEL_DELTA_WPARAM(wparam)) / f32(win32.WHEEL_DELTA)
//         event := Mouse_Wheel_Event{ delta, 0 }
//         dispatch_event(event)
//         return 0
//     }

//     return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
// }

// _win32_get_mouse_pos :: proc "contextless" (lparam: win32.LPARAM) -> Vec2f {
//     x := f32(win32.GET_X_LPARAM(lparam))
//     y := f32(win32.GET_Y_LPARAM(lparam))
//     return Vec2f{ x, y }
// }

// _win32_keyboard_to_key :: proc "contextless" (key: win32.WPARAM, flags: win32.LPARAM) -> Key {
//     switch key {
//     // Check the scancode to distinguish between left and right shift
//     case win32.VK_SHIFT:
//         lShift := win32.MapVirtualKeyW(win32.VK_LSHIFT, win32.MAPVK_VK_TO_VSC)
//         scancode := win32.UINT((flags & (0xFF << 16)) >> 16)
//         return scancode == lShift ? .L_Shift : .R_Shift

//     // Check the "extended" flag to distinguish between left and right alt
//     case win32.VK_MENU:
//         return .R_Alt if (win32.HIWORD(flags) & win32.KF_EXTENDED) != 0 else .L_Alt

//     // Check the "extended" flag to distinguish between left and right control
//     case win32.VK_CONTROL:
//         return .R_Control if (win32.HIWORD(flags) & win32.KF_EXTENDED) != 0 else .L_Control

//     // Other keys are reported properly
//     case win32.VK_LWIN:       return .L_System
//     case win32.VK_RWIN:       return .R_System
//     case win32.VK_APPS:       return .Menu
//     case win32.VK_OEM_1:      return .Semicolon
//     case win32.VK_OEM_2:      return .Slash
//     case win32.VK_OEM_PLUS:   return .Equal
//     case win32.VK_OEM_MINUS:  return .Hyphen
//     case win32.VK_OEM_4:      return .L_Bracket
//     case win32.VK_OEM_6:      return .R_Bracket
//     case win32.VK_OEM_COMMA:  return .Comma
//     case win32.VK_OEM_PERIOD: return .Period
//     case win32.VK_OEM_7:      return .Apostrophe
//     case win32.VK_OEM_5:      return .Backslash
//     case win32.VK_OEM_3:      return .Grave
//     case win32.VK_ESCAPE:     return .Escape
//     case win32.VK_SPACE:      return .Space
//     case win32.VK_RETURN:     return .Enter
//     case win32.VK_BACK:       return .Backspace
//     case win32.VK_TAB:        return .Tab
//     case win32.VK_PRIOR:      return .Page_Up
//     case win32.VK_NEXT:       return .Page_Down
//     case win32.VK_END:        return .End
//     case win32.VK_HOME:       return .Home
//     case win32.VK_INSERT:     return .Insert
//     case win32.VK_DELETE:     return .Delete
//     case win32.VK_ADD:        return .Add
//     case win32.VK_SUBTRACT:   return .Subtract
//     case win32.VK_MULTIPLY:   return .Multiply
//     case win32.VK_DIVIDE:     return .Divide
//     case win32.VK_PAUSE:      return .Pause
//     case win32.VK_F1:         return .F1
//     case win32.VK_F2:         return .F2
//     case win32.VK_F3:         return .F3
//     case win32.VK_F4:         return .F4
//     case win32.VK_F5:         return .F5
//     case win32.VK_F6:         return .F6
//     case win32.VK_F7:         return .F7
//     case win32.VK_F8:         return .F8
//     case win32.VK_F9:         return .F9
//     case win32.VK_F10:        return .F10
//     case win32.VK_F11:        return .F11
//     case win32.VK_F12:        return .F12
//     case win32.VK_F13:        return .F13
//     case win32.VK_F14:        return .F14
//     case win32.VK_F15:        return .F15
//     case win32.VK_LEFT:       return .Left
//     case win32.VK_RIGHT:      return .Right
//     case win32.VK_UP:         return .Up
//     case win32.VK_DOWN:       return .Down
//     case win32.VK_NUMPAD0:    return .Numpad0
//     case win32.VK_NUMPAD1:    return .Numpad1
//     case win32.VK_NUMPAD2:    return .Numpad2
//     case win32.VK_NUMPAD3:    return .Numpad3
//     case win32.VK_NUMPAD4:    return .Numpad4
//     case win32.VK_NUMPAD5:    return .Numpad5
//     case win32.VK_NUMPAD6:    return .Numpad6
//     case win32.VK_NUMPAD7:    return .Numpad7
//     case win32.VK_NUMPAD8:    return .Numpad8
//     case win32.VK_NUMPAD9:    return .Numpad9
//     case 'A':                 return .A
//     case 'Z':                 return .Z
//     case 'E':                 return .E
//     case 'R':                 return .R
//     case 'T':                 return .T
//     case 'Y':                 return .Y
//     case 'U':                 return .U
//     case 'I':                 return .I
//     case 'O':                 return .O
//     case 'P':                 return .P
//     case 'Q':                 return .Q
//     case 'S':                 return .S
//     case 'D':                 return .D
//     case 'F':                 return .F
//     case 'G':                 return .G
//     case 'H':                 return .H
//     case 'J':                 return .J
//     case 'K':                 return .K
//     case 'L':                 return .L
//     case 'M':                 return .M
//     case 'W':                 return .W
//     case 'X':                 return .X
//     case 'C':                 return .C
//     case 'V':                 return .V
//     case 'B':                 return .B
//     case 'N':                 return .N
//     case '0':                 return .Num0
//     case '1':                 return .Num1
//     case '2':                 return .Num2
//     case '3':                 return .Num3
//     case '4':                 return .Num4
//     case '5':                 return .Num5
//     case '6':                 return .Num6
//     case '7':                 return .Num7
//     case '8':                 return .Num8
//     case '9':                 return .Num9
//     case:                     return .Unknown
//     }
// }

// _win32_keyboard_to_scancode :: proc "contextless" (
//     wParam: win32.WPARAM,
//     lParam: win32.LPARAM,
// ) -> Scancode {
//     code := (lParam & (0xFF << 16)) >> 16

//     extended := (win32.HIWORD(lParam) & win32.KF_EXTENDED) != 0

//     // Windows scancodes
//     // Reference: https://msdn.microsoft.com/en-us/library/aa299374(v=vs.60).aspx
//     switch code {
//     case 1:   return .Escape
//     case 2:   return .Num1
//     case 3:   return .Num2
//     case 4:   return .Num3
//     case 5:   return .Num4
//     case 6:   return .Num5
//     case 7:   return .Num6
//     case 8:   return .Num7
//     case 9:   return .Num8
//     case 10:  return .Num9
//     case 11:  return .Num0
//     case 12:  return .Hyphen
//     case 13:  return .Equal
//     case 14:  return .Backspace
//     case 15:  return .Tab
//     case 16:  return .Media_Previous_Track if extended else .Q
//     case 17:  return .W
//     case 18:  return .E
//     case 19:  return .R
//     case 20:  return .T
//     case 21:  return .Y
//     case 22:  return .U
//     case 23:  return .I
//     case 24:  return .O
//     case 25:  return .Media_Next_Track if extended else .P
//     case 26:  return .L_Bracket
//     case 27:  return .R_Bracket
//     case 28:  return .Numpad_Enter if extended else .Enter
//     case 29:  return .R_Control if extended else .L_Control
//     case 30:  return .Select if extended else .A
//     case 31:  return .S
//     case 32:  return .Volume_Mute if extended else .D
//     case 33:  return .Launch_Application1 if extended else .F
//     case 34:  return .Media_Play_Pause if extended else .G
//     case 35:  return .H
//     case 36:  return .Media_Stop if extended else .J
//     case 37:  return .K
//     case 38:  return .L
//     case 39:  return .Semicolon
//     case 40:  return .Apostrophe
//     case 41:  return .Grave
//     case 42:  return .L_Shift
//     case 43:  return .Backslash
//     case 44:  return .Z
//     case 45:  return .X
//     case 46:  return .Volume_Down if extended else .C
//     case 47:  return .V
//     case 48:  return .Volume_Up if extended else .B
//     case 49:  return .N
//     case 50:  return .Home_Page if extended else .M
//     case 51:  return .Comma
//     case 52:  return .Period
//     case 53:  return .Numpad_Divide if extended else .Slash
//     case 54:  return .R_Shift
//     case 55:  return .Print_Screen if extended else .Numpad_Multiply
//     case 56:  return .R_Alt if extended else .L_Alt
//     case 57:  return .Space
//     case 58:  return .Caps_Lock
//     case 59:  return .F1
//     case 60:  return .F2
//     case 61:  return .F3
//     case 62:  return .F4
//     case 63:  return .F5
//     case 64:  return .F6
//     case 65:  return .F7
//     case 66:  return .F8
//     case 67:  return .F9
//     case 68:  return .F10
//     case 69:  return .Num_Lock if extended else .Pause
//     case 70:  return .Scroll_Lock
//     case 71:  return .Home if extended else .Numpad7
//     case 72:  return .Up if extended else .Numpad8
//     case 73:  return .Page_Up if extended else .Numpad9
//     case 74:  return .Numpad_Minus
//     case 75:  return .Left if extended else .Numpad4
//     case 76:  return .Numpad5
//     case 77:  return .Right if extended else .Numpad6
//     case 78:  return .Numpad_Plus
//     case 79:  return .End if extended else .Numpad1
//     case 80:  return .Down if extended else .Numpad2
//     case 81:  return .Page_Down if extended else .Numpad3
//     case 82:  return .Insert if extended else .Numpad0
//     case 83:  return .Delete if extended else .Numpad_Decimal
//     case 86:  return .Non_Us_Backslash
//     case 87:  return .F11
//     case 88:  return .F12
//     case 91:  return .L_System if extended else .Unknown
//     case 92:  return .R_System if extended else .Unknown
//     case 93:  return .Menu if extended else .Unknown
//     case 99:  return .Help if extended else .Unknown
//     case 100: return .F13
//     case 101: return .Search if extended else .F14
//     case 102: return .Favorites if extended else .F15
//     case 103: return .Refresh if extended else .F16
//     case 104: return .Stop if extended else .F17
//     case 105: return .Forward if extended else .F18
//     case 106: return .Back if extended else .F19
//     case 107: return .Launch_Application1 if extended else .F20
//     case 108: return .Launch_Mail if extended else .F21
//     case 109: return .Launch_Media_Select if extended else .F22
//     case 110: return .F23
//     case 118: return .F24
//     case:     return .Unknown
//     }
// }
