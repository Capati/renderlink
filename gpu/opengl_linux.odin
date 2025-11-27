#+build linux
package gpu

GL_Active_Context :: struct {}

gl_active_context_init :: proc(self: ^GL_Active_Context, loc := #caller_location) {
}

gl_active_context_deinit :: proc(self: ^GL_Active_Context) {
}

GL_Context :: struct {}

GL_Instance_Impl :: struct {
    using base: Instance,
}

@(require_results)
gl_linux_create_instance :: proc(
    descriptor: Maybe(Instance_Descriptor) = nil,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    ret: ^Instance,
    ok: bool,
) {
    return
}

@(require_results)
gl_linux_instance_create_surface :: proc(
    instance: ^Instance,
    descriptor: Surface_Descriptor,
    loc := #caller_location,
) -> (
    ret: ^Surface,
    ok: bool,
) {
    // impl := gl_instance_get_impl(instance, loc)
    return
}

gl_linux_instance_release :: proc(instance: ^Instance, loc := #caller_location) {
    // impl := gl_instance_get_impl(instance, loc)
}

// -----------------------------------------------------------------------------
// Surface
// -----------------------------------------------------------------------------

GL_Surface_Impl :: struct {
    using base: Surface,
}
