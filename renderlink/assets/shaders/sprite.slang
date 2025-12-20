struct Uniforms {
    float4x4 transform;
};

struct VertexInput {
    float3 position : POSITION;
    float2 tex_coords : TEXCOORD0;
    float4 color : COLOR;
};

struct VertexOutput {
    float4 clip_position : SV_POSITION;
    float2 tex_coords : TEXCOORD0;
    float4 color : COLOR;
    float3 world_position : TEXCOORD1;
};

[[vk::binding(0, 0)]]
ConstantBuffer<Uniforms> uniforms : register(b0);

[shader("vertex")]
VertexOutput vs_main(VertexInput input) {
    VertexOutput output;

    output.tex_coords = input.tex_coords;
    output.clip_position = mul(uniforms.transform, float4(input.position, 1.0));
    output.color = input.color;
    output.world_position = input.position;

    return output;
}

struct FragmentInput {
    float4 clip_position : SV_POSITION;
    float2 tex_coord : TEXCOORD0;
    float4 color : COLOR;
    float3 world_position : TEXCOORD1;
};

#if defined(USE_COMBINED_SAMPLER)

[[vk::binding(1, 0)]]
Sampler2D s_diffuse : register(t1);

#else

[[vk::binding(1, 0)]]
Texture2D s_diffuse : register(t1);

[[vk::binding(2, 0)]]
SamplerState s_sampler : register(s2);

#endif

[shader("fragment")]
float4 fs_main(FragmentInput in) : SV_Target {
    float4 tex_color;

#if defined(USE_COMBINED_SAMPLER)
    tex_color = s_diffuse.Sample(in.tex_coord);
#else
    tex_color = s_diffuse.Sample(s_sampler, in.tex_coord);
#endif

    float4 base_color = tex_color * in.color;
    return base_color;
}
