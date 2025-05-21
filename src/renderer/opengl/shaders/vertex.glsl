#version 330 core
layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aTex;

uniform mat4 projection;

out vec2 TexCoords;

void main() {
    gl_Position = projection * vec4(aPos.xy, 0.0, 1.0);
    TexCoords = aTex;
}
