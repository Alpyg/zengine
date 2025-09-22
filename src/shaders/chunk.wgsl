@group(0) @binding(0) var<uniform> object_to_clip: mat4x4<f32>;
@group(0) @binding(1) var<storage, read> face_buffer: array<Face>;
@group(0) @binding(2) var<storage, read> quad_buffer: array<Quad>;
@group(0) @binding(3) var texture_image: texture_2d<f32>;
@group(0) @binding(4) var texture_sampler: sampler;

struct Face {
    pos: u32,
    data: u32,
}

struct Quad {
    vertex: array<vec4<f32>, 4>,
}

struct VertexOut {
    @builtin(position) position_clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) @interpolate(flat) tex_idx: u32,
}

@vertex fn vertex(
    @builtin(vertex_index) vertex_idx: u32,
) -> VertexOut {
    let face_idx = vertex_idx / 6;
    let corner_idx = vertex_idx % 6;

    let face = face_buffer[face_idx];

    let x = f32((face.pos >> 0u) & 0x1Fu);
    let y = f32((face.pos >> 5u) & 0x3FFu);
    let z = f32((face.pos >> 16u) & 0x1Fu);
    let tex = (face.data >> 0u) & 0xFFFFu;
    let qid = (face.data >> 16u) & 0xFFFFu;

    let corners = array<u32, 6>(0, 1, 2, 0, 2, 3);
    let corner = corners[corner_idx];

    let quad = quad_buffer[qid];
    let pos = quad.vertex[corner].xyz;
    let uv = unpack2x16float(bitcast<u32>(quad.vertex[corner].w));

    var out: VertexOut;
    out.position_clip = (vec4<f32>(x, y, z, 1.0) + vec4<f32>(pos, 1.0)) * object_to_clip;
    out.uv = uv;
    out.tex_idx = tex;

    return out;
}

@fragment fn fragment(
    @location(0) uv: vec2<f32>,
    @location(1) @interpolate(flat) texture_index: u32,
) -> @location(0) vec4<f32> {
    let size = textureDimensions(texture_image, 0u);
    let tile_size = vec2<u32>(16, 16);
    
    let row_tiles = size.x / tile_size.x;

    let tile = vec2<u32>(
        texture_index % row_tiles,
        texture_index / row_tiles
    );
    let texture_uv = (vec2<f32>(tile) * vec2<f32>(tile_size) + uv) / vec2<f32>(size);
    
    let color = textureSample(texture_image, texture_sampler, texture_uv);

    return color;
}
