#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 5 "renderlink/assets/shaders/sprite.slang"
struct vs_main_Result_0
{
    float4 clip_position_0 [[position]];
    float2 tex_coords_0 [[user(TEXCOORD)]];
    float4 color_0 [[user(COLOR)]];
    float3 world_position_0 [[user(TEXCOORD_1)]];
};


#line 5
struct vertexInput_0
{
    float3 position_0 [[attribute(0)]];
    float2 tex_coords_1 [[attribute(1)]];
    float4 color_1 [[attribute(2)]];
};


#line 5
struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};


#line 5
struct Uniforms_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 transform_0;
};


struct VertexOutput_0
{
    float4 clip_position_1;
    float2 tex_coords_2;
    float4 color_2;
    float3 world_position_1;
};


#line 11
[[vertex]] vs_main_Result_0 vs_main(vertexInput_0 _S1 [[stage_in]], Uniforms_natural_0 constant* uniforms_0 [[buffer(0)]])
{

#line 23
    thread VertexOutput_0 output_0;

    (&output_0)->tex_coords_2 = _S1.tex_coords_1;
    (&output_0)->clip_position_1 = (((float4(_S1.position_0, 1.0)) * (matrix<float,int(4),int(4)> (uniforms_0->transform_0.data_0[int(0)][int(0)], uniforms_0->transform_0.data_0[int(1)][int(0)], uniforms_0->transform_0.data_0[int(2)][int(0)], uniforms_0->transform_0.data_0[int(3)][int(0)], uniforms_0->transform_0.data_0[int(0)][int(1)], uniforms_0->transform_0.data_0[int(1)][int(1)], uniforms_0->transform_0.data_0[int(2)][int(1)], uniforms_0->transform_0.data_0[int(3)][int(1)], uniforms_0->transform_0.data_0[int(0)][int(2)], uniforms_0->transform_0.data_0[int(1)][int(2)], uniforms_0->transform_0.data_0[int(2)][int(2)], uniforms_0->transform_0.data_0[int(3)][int(2)], uniforms_0->transform_0.data_0[int(0)][int(3)], uniforms_0->transform_0.data_0[int(1)][int(3)], uniforms_0->transform_0.data_0[int(2)][int(3)], uniforms_0->transform_0.data_0[int(3)][int(3)]))));
    (&output_0)->color_2 = _S1.color_1;
    (&output_0)->world_position_1 = _S1.position_0;

#line 28
    thread vs_main_Result_0 _S2;

#line 28
    (&_S2)->clip_position_0 = output_0.clip_position_1;

#line 28
    (&_S2)->tex_coords_0 = output_0.tex_coords_2;

#line 28
    (&_S2)->color_0 = output_0.color_2;

#line 28
    (&_S2)->world_position_0 = output_0.world_position_1;

#line 28
    return _S2;
}

