#version 450
layout(row_major) uniform;
layout(row_major) buffer;

#line 2 0
struct Uniforms_natural_0
{
    mat4x4 transform_0;
};


#line 19
layout(binding = 0)
layout(std140) uniform block_Uniforms_natural_0
{
    mat4x4 transform_0;
}uniforms_0;

#line 5
layout(location = 0)
out vec2 entryPointParam_vs_main_tex_coords_0;


#line 5
layout(location = 1)
out vec4 entryPointParam_vs_main_color_0;


#line 5
layout(location = 2)
out vec3 entryPointParam_vs_main_world_position_0;


#line 5
layout(location = 0)
in vec3 input_position_0;


#line 5
layout(location = 1)
in vec2 input_tex_coords_0;


#line 5
layout(location = 2)
in vec4 input_color_0;




struct VertexOutput_0
{
    vec4 clip_position_0;
    vec2 tex_coords_0;
    vec4 color_0;
    vec3 world_position_0;
};




void main()
{

#line 23
    VertexOutput_0 output_0;

    output_0.tex_coords_0 = input_tex_coords_0;
    output_0.clip_position_0 = (((vec4(input_position_0, 1.0)) * (uniforms_0.transform_0)));
    output_0.color_0 = input_color_0;
    output_0.world_position_0 = input_position_0;

    VertexOutput_0 _S1 = output_0;

#line 30
    gl_Position = output_0.clip_position_0;

#line 30
    entryPointParam_vs_main_tex_coords_0 = _S1.tex_coords_0;

#line 30
    entryPointParam_vs_main_color_0 = _S1.color_0;

#line 30
    entryPointParam_vs_main_world_position_0 = _S1.world_position_0;

#line 30
    return;
}

