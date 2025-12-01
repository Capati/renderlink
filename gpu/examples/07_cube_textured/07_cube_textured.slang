struct Uniforms {
    float4x4 transform;
};

struct VertexInput {
    float4 position : POSITION;
    float2 tex_coord : TEXCOORD0;
};

struct VertexOutput {
    float4 position : SV_Position;
    float2 tex_coord : TEXCOORD0;
};

[[vk::binding(0, 0)]]
ConstantBuffer<Uniforms> uniforms;

[shader("vertex")]
VertexOutput vs_main(VertexInput input) {
    VertexOutput output;
    output.tex_coord = input.tex_coord;
    output.position = mul(uniforms.transform, input.position);
    return output;
}

struct FragmentInput {
    float2 tex_coord : TEXCOORD0;
};

[[vk::binding(1, 0)]]
Sampler2D r_color;

[shader("fragment")]
float4 fs_main(FragmentInput input) : SV_Target {
    float4 tex = r_color.Sample(input.tex_coord);
    float v = tex.x;
    float3 color = float3(1.0 - (v * 5.0), 1.0 - (v * 15.0), 1.0 - (v * 50.0));
    return float4(color, 1.0);
}
