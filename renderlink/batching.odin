package renderlink

// Core
import "base:runtime"
import "core:mem"
import "core:slice"
// import "core:sync"

Render_Queue_List :: struct {
    data:      [dynamic]Mesh,
    allocator: mem.Allocator,
}

Render_Queue_Map :: map[Mesh_Key]Render_Queue_List

Render_Queues :: struct {
    data:      Render_Queue_Map,
    allocator: mem.Allocator,
    arena:     mem.Dynamic_Arena,
}

Batch_Data :: struct {
    key:           Mesh_Key,
    vertex_count:  u32,
    index_count:   u32,
    vertex_offset: u32,
    index_offset:  u32,
}

render_queues_init :: proc(self: ^Render_Queues, allocator := context.allocator) {
    assert(self != nil, "Invalid render queues object")
    self.data = make(Render_Queue_Map, 64, allocator) // Pre-allocate some size
    self.allocator = allocator
    mem.dynamic_arena_init(&self.arena)
}

render_queues_destroy :: proc(self: ^Render_Queues) {
    assert(self != nil, "Invalid render queues object")
    mem.dynamic_arena_destroy(&self.arena)
    delete(self.data)
}

render_queues_free :: proc(self: ^Render_Queues) {
    mem.dynamic_arena_reset(&self.arena)
    clear(&self.data)
}

push_mesh :: proc(ctx: ^Context, mesh: Mesh, blend_mode: Blend_Mode) #no_bounds_check {
    shader := ctx.sprite_shader
    render_target: Render_Target

    texture_to_use := mesh.texture
    if !texture_is_valid(mesh.texture) {
        // Use the default solid color texture
        texture_to_use = ctx.default_texture
    }

    key := Mesh_Key {
        z_index       = mesh.z_index,
        blend_mode    = blend_mode,
        texture       = texture_to_use,
        shader        = shader,
        render_target = render_target,
    }

    queue, exists := &ctx.render_queues.data[key]
    if !exists {
        arena_alloc := mem.dynamic_arena_allocator(&ctx.render_queues.arena)
        ctx.render_queues.data[key] = {
            data      = make([dynamic]Mesh, 0, 256, arena_alloc), // Pre-allocate capacity
            allocator = arena_alloc,
        }
        queue = &ctx.render_queues.data[key]
    }

    append(&queue.data, mesh)
}

@(optimization_mode="favor_size")
prepare_batches :: proc(
    ctx: ^Context,
    arena_alloc: mem.Allocator,
) -> []Batch_Data #no_bounds_check {
    ta := context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    sorted_keys := make([dynamic]Mesh_Key, 0, len(ctx.render_queues.data), ta)

    // Sort meshes within each queue and collect non-empty keys
    for key, &meshes in ctx.render_queues.data {
        mesh_count := len(meshes.data)
        if mesh_count == 0 do continue

        // Uses the Y-sort setting for this Z-index
        if mesh_count > 1 && y_sort_get(ctx, key.z_index) {
            slice.sort_by_key(meshes.data[:], proc(mesh: Mesh) -> f32 {
                return -(mesh.origin.y + mesh.y_sort_offset)
            })
        }

        append(&sorted_keys, key)
    }

    // Sort batches by Z-index
    slice.sort_by_key(sorted_keys[:], proc(k: Mesh_Key) -> int { return k.z_index })

    batches := make([dynamic]Batch_Data, 0, len(sorted_keys), arena_alloc)

    // Pre-clear and reserve capacity
    clear(&ctx.staging_vertices)
    clear(&ctx.staging_indices)

    // First pass: calculate total size
    total_vertices := 0
    total_indices := 0

    for &key in sorted_keys {
        meshes := ctx.render_queues.data[key].data[:]
        for i := 0; i < len(meshes); i += 1 {
            total_vertices += len(meshes[i].vertices)
            total_indices += len(meshes[i].indices)
        }
    }

    if cap(ctx.staging_vertices) < total_vertices {
        reserve(&ctx.staging_vertices, total_vertices * 2) // Over-allocate for next frame
    }
    if cap(ctx.staging_indices) < total_indices {
        reserve(&ctx.staging_indices, total_indices * 2)
    }

    // Resize buffers once to final size
    non_zero_resize(&ctx.staging_vertices, total_vertices)
    non_zero_resize(&ctx.staging_indices, total_indices)

    vertex_write_pos := 0
    index_write_pos := 0

    for &key in sorted_keys {
        meshes := ctx.render_queues.data[key].data[:]
        mesh_count := len(meshes)

        if mesh_count == 0 do continue

        // Count vertices/indices for this batch
        vertex_count := 0
        index_count := 0
        for i := 0; i < mesh_count; i += 1 {
            vertex_count += len(meshes[i].vertices)
            index_count += len(meshes[i].indices)
        }

        if vertex_count == 0 || index_count == 0 do continue

        // Record batch info
        append(
            &batches,
            Batch_Data{
                key           = key,
                vertex_count  = u32(vertex_count),
                index_count   = u32(index_count),
                vertex_offset = u32(vertex_write_pos),
                index_offset  = u32(index_write_pos),
            },
        )

        // Build geometry immediately
        current_vertex_base: u32 = 0

        for i := 0; i < mesh_count; i += 1 {
            mesh := &meshes[i]
            vertex_len := len(mesh.vertices)
            index_len := len(mesh.indices)

            // Bulk copy vertices
            if vertex_len > 0 {
                mem.copy_non_overlapping(
                    raw_data(ctx.staging_vertices[vertex_write_pos:]),
                    raw_data(mesh.vertices[:]),
                    vertex_len * size_of(mesh.vertices[0]),
                )
                vertex_write_pos += vertex_len
            }

            // Bulk copy and adjust indices
            if index_len > 0 {
                indices_dest := ctx.staging_indices[index_write_pos:]
                indices_src := mesh.indices[:]
                for j := 0; j < index_len; j += 1 {
                    indices_dest[j] = indices_src[j] + current_vertex_base
                }
                index_write_pos += index_len
            }

            current_vertex_base += u32(vertex_len)
        }
    }

    // Upload all geometry at once
    if len(ctx.staging_vertices) > 0 && len(ctx.staging_indices) > 0 {
        sized_buffer_copy(&ctx.vertex_buffer, ctx.base.queue, to_bytes(ctx.staging_vertices[:]))
        sized_buffer_copy(&ctx.index_buffer, ctx.base.queue, to_bytes(ctx.staging_indices[:]))
    }

    return batches[:]
}

Y_Sort_State :: struct {
    data:      map[int]bool,
    // mutex:     sync.RW_Mutex,
    allocator: mem.Allocator,
}

y_sort_init :: proc(self: ^Y_Sort_State, allocator := context.allocator) {
    assert(self != nil, "Invalid y sort flags object")
    // sync.guard(&self.mutex)
    self.data = make(map[int]bool, 16, allocator) // Pre-allocate
    self.allocator = allocator
}

y_sort_destroy :: proc(self: ^Y_Sort_State) {
    context.allocator = self.allocator
    delete(self.data)
}

y_sort_set :: proc(ctx: ^Context, z_index: int, enabled: bool) {
    // sync.guard(&ctx.y_sort_state.mutex)
    ctx.y_sort_state.data[z_index] = enabled
}

y_sort_get :: #force_inline proc(ctx: ^Context, z_index: int) -> bool {
    // sync.shared_guard(&ctx.y_sort_state.mutex)
    #no_bounds_check return ctx.y_sort_state.data[z_index] or_else false
}

y_sort_remove :: proc(ctx: ^Context, z_index: int) {
    // sync.guard(&ctx.y_sort_state.mutex)
    delete_key(&ctx.y_sort_state.data, z_index)
}

y_sort_clear :: proc(ctx: ^Context, z_index: int) {
    // sync.guard(&ctx.y_sort_state.mutex)
    clear(&ctx.y_sort_state.data)
}
