#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 90 "core"
struct pixelOutput_0
{
    float4 output_0 [[color(0)]];
};


#line 2306 "core.meta.slang"
struct pixelInput_0
{
    float2 tex_coord_0 [[user(TEXCOORD)]];
    float4 color_0 [[user(COLOR)]];
    float3 world_position_0 [[user(TEXCOORD_1)]];
};


#line 2306
struct KernelContext_0
{
    texture2d<float, access::sample> s_diffuse_0;
    sampler s_sampler_0;
};


#line 56 "renderlink/assets/shaders/sprite.slang"
[[fragment]] pixelOutput_0 fs_main(pixelInput_0 _S1 [[stage_in]], float4 clip_position_0 [[position]], texture2d<float, access::sample> s_diffuse_1 [[texture(1)]], sampler s_sampler_1 [[sampler(2)]])
{

#line 56
    KernelContext_0 kernelContext_0;

#line 56
    (&kernelContext_0)->s_diffuse_0 = s_diffuse_1;

#line 56
    (&kernelContext_0)->s_sampler_0 = s_sampler_1;

#line 56
    pixelOutput_0 _S2 = { (((&kernelContext_0)->s_diffuse_0).sample((s_sampler_1), (_S1.tex_coord_0))) * _S1.color_0 };

#line 66
    return _S2;
}

