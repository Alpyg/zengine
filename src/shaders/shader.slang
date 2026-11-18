struct VSInput {
    [[vk::location(0)]] float3 position;
    [[vk::location(1)]] float3 color;
};

struct VSOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float3 color;
};

struct Uniforms {
    float4x4 object_to_clip;
};

// SDL3 GPU convention: vertex uniform data is set 1, binding 0.
[[vk::binding(0, 1)]]
ConstantBuffer<Uniforms> ubo;

[shader("vertex")]
VSOutput vertex(VSInput input) {
    VSOutput output;
    // zmath uses row vectors; `mul(matrix, vector)` lowers to the same
    // `OpVectorTimesMatrix` as the previous GLSL `vec4(position, 1.0) * m`.
    output.position = mul(ubo.object_to_clip, float4(input.position, 1.0));
    output.color = input.color;
    return output;
}

[shader("fragment")]
float4 fragment(VSOutput input) : SV_Target {
    return float4(input.color, 1.0);
}
