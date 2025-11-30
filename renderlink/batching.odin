package renderlink

// Core
import "core:mem"
import "core:slice"
import sa "core:container/small_array"
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
    self.data = make(Render_Queue_Map, allocator)
    self.allocator = allocator
    mem.dynamic_arena_init(&self.arena)
}

render_queues_destroy :: proc(self: ^Render_Queues) {
    assert(self != nil, "Invalid render queues object")
    mem.dynamic_arena_destroy(&self.arena)
    delete(self.data)
}

render_queues_free :: proc(self: ^Render_Queues) {
    mem.dynamic_arena_free_all(&self.arena)
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
            data      = make([dynamic]Mesh, arena_alloc),
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
    sorted_keys := make([dynamic]Mesh_Key, arena_alloc)

    // Sort meshes within each queue and collect non-empty keys
    for key, &meshes in ctx.render_queues.data {
        if len(meshes.data) == 0 do continue

        // Uses the Y-sort setting for this Z-index
        if y_sort_get(ctx, key.z_index) {
            slice.sort_by_key(meshes.data[:], proc(mesh: Mesh) -> f32 {
                return -(mesh.origin.y + mesh.y_sort_offset)
            })
        }

        append(&sorted_keys, key)
    }

    // Sort batches by Z-index
    slice.sort_by_key(sorted_keys[:], proc(k: Mesh_Key) -> int {
        return k.z_index
    })

    batches := make([dynamic]Batch_Data, arena_alloc)

    // Calculate total geometry requirements
    total_vertices := 0
    total_indices := 0

    for &key in sorted_keys {
        meshes := &(&ctx.render_queues.data[key]).data

        vertex_count: int
        index_count: int

        for &mesh in meshes {
            vertex_count += sa.len(mesh.vertices)
            index_count += sa.len(mesh.indices)
        }

        if vertex_count == 0 || index_count == 0 do continue

        total_vertices += vertex_count
        total_indices += index_count

        append(
            &batches,
            Batch_Data{
                key           = key,
                vertex_count  = u32(vertex_count),
                index_count   = u32(index_count),
                vertex_offset = 0, // Will be updated below
                index_offset  = 0,
            },
        )
    }

    if len(batches) == 0 do return batches[:]

    // Reuse staging buffers instead of allocating
    clear(&ctx.staging_vertices)
    clear(&ctx.staging_indices)

    // Reserve capacity if needed
    if cap(ctx.staging_vertices) < total_vertices {
        reserve(&ctx.staging_vertices, total_vertices)
    }
    if cap(ctx.staging_indices) < total_indices {
        reserve(&ctx.staging_indices, total_indices)
    }

    // Build geometry (no more temp allocator)
    for &batch in batches {
        batch.vertex_offset = u32(len(ctx.staging_vertices))
        batch.index_offset = u32(len(ctx.staging_indices))

        meshes := ctx.render_queues.data[batch.key].data

        // Append all vertices at once and append indices in batches
        current_vertex_base := u32(0)
        for &mesh in meshes {
            // Copy vertices from Small_Array
            for i in 0..<sa.len(mesh.vertices) {
                append(&ctx.staging_vertices, sa.get(mesh.vertices, i))
            }

            vertex_count := sa.len(mesh.vertices)
            index_count := sa.len(mesh.indices)

            if index_count == 0 do continue

            index_start := len(ctx.staging_indices)
            resize(&ctx.staging_indices, len(ctx.staging_indices) + index_count)

            // Copy indices from Small_Array and adjust by vertex base
            for i in 0..<index_count {
                ctx.staging_indices[index_start + i] = sa.get(mesh.indices, i) + current_vertex_base
            }

            current_vertex_base += u32(vertex_count)
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
    self.data = make(map[int]bool, allocator)
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
