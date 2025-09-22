@group(0) @binding(0) var<uniform> object_to_clip: mat4x4<f32>;
@group(0) @binding(1) var texture_image: texture_2d<f32>;
@group(0) @binding(2) var texture_sampler: sampler;

struct VertexOut {
    @builtin(position) position_clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
}

@vertex fn vertex(
    @location(0) position: vec3<f32>,
    @location(1) uv: vec2<f32>,
) -> VertexOut {
    var output: VertexOut;
    output.position_clip = vec4(position, 1.0) * object_to_clip;
    output.uv = uv;
    return output;
}

@fragment fn fragment(
    @location(0) uv: vec2<f32>,
) -> @location(0) vec4<f32> {
    return textureSample(texture_image, texture_sampler, uv);
}
