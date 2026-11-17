#version 450

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 color;

layout(location = 0) out vec3 v_color;

layout(set = 1, binding = 0) uniform UBO {
    mat4 object_to_clip;
};

void main() {
    gl_Position = vec4(position, 1.0) * object_to_clip;
    v_color = color;
}
