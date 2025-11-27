@binding(1) @group(0) var s_diffuse_texture_0 : texture_2d<f32>;

@binding(2) @group(0) var s_diffuse_sampler_0 : sampler;

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) tex_coord_0 : vec2<f32>,
    @location(2) color_0 : vec4<f32>,
    @location(1) world_position_0 : vec3<f32>,
};

@fragment
fn fs_main( _S1 : pixelInput_0) -> pixelOutput_0
{
    ;
    var _S2 : pixelOutput_0 = pixelOutput_0( (textureSample((s_diffuse_texture_0), (s_diffuse_sampler_0), (_S1.tex_coord_0))) * _S1.color_0 );
    return _S2;
}

