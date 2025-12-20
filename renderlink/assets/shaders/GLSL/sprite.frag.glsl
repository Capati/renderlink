#version 450
layout(row_major) uniform;
layout(row_major) buffer;

#line 43 0
layout(binding = 1)
uniform sampler2D s_diffuse_0;


#line 977 1
layout(location = 0)
out vec4 entryPointParam_fs_main_0;


#line 977
layout(location = 0)
in vec2 in_tex_coord_0;


#line 977
layout(location = 1)
in vec4 in_color_0;


#line 56 0
void main()
{

#line 56
    entryPointParam_fs_main_0 = (texture((s_diffuse_0), (in_tex_coord_0))) * in_color_0;

#line 56
    return;
}

