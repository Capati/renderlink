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
    texture2d<float, access::sample> s_diffuse_texture_0;
    sampler s_diffuse_sampler_0;
};


#line 43 "renderlink/assets/shaders/sprite.slang"
[[fragment]] pixelOutput_0 fs_main(pixelInput_0 _S1 [[stage_in]], texture2d<float, access::sample> s_diffuse_texture_1 [[texture(0)]], sampler s_diffuse_sampler_1 [[sampler(0)]])
{

#line 43
    KernelContext_0 kernelContext_0;

#line 43
    (&kernelContext_0)->s_diffuse_texture_0 = s_diffuse_texture_1;

#line 43
    (&kernelContext_0)->s_diffuse_sampler_0 = s_diffuse_sampler_1;
    ;

#line 44
    pixelOutput_0 _S2 = { (((&kernelContext_0)->s_diffuse_texture_0).sample(((&kernelContext_0)->s_diffuse_sampler_0), (_S1.tex_coord_0))) * _S1.color_0 };

    return _S2;
}

