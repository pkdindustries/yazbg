#version 100
precision mediump float;

// nearest_cell_es100.fs – fragment shader blending a sprite with the colour of
// the nearest occupied Tetris cell on the play-field.

// Attributes from the vertex shader
varying vec2 fragTexCoord;
varying vec4 fragColor;

// Uniforms
uniform sampler2D texture0;   // sprite texture (bound by rlgl)
uniform sampler2D boardTex;   // 10×20 grid texture holding cell colours

uniform vec2 gridSize;       // (10,20) in floats – cast to int in shader
uniform vec2 cellSize;       // pixels
uniform vec2 spritePos;      // top-left corner of the sprite (pixels)
uniform vec2 spriteSize;     // pixels (width,height)
uniform float time;          // seconds
uniform vec4 colDiffuse;     // global tint supplied by raylib

void main() {
    // Fetch the sprite texel first.
    vec4 spriteTexel = texture2D(texture0, fragTexCoord) * fragColor * colDiffuse;

    // Compute the fragment’s world-space pixel position.
    vec2 worldPx = spritePos + fragTexCoord * spriteSize;

    // Determine the grid coordinate nearest to this pixel.
    vec2 cellCoord = floor(worldPx / cellSize);

    // Clamp to board area in case the sprite overlaps the border.
    vec2 gridLimits = gridSize - vec2(1.0);
    cellCoord = clamp(cellCoord, vec2(0.0), gridLimits);

    // Convert cell coordinate into UV for boardTex.
    vec2 boardUV = (cellCoord + vec2(0.5)) / gridSize;
    vec4 cellColour = texture2D(boardTex, boardUV);

    // Early out: if the cell is empty keep original texel.
    if (cellColour.a < 0.01) {
        gl_FragColor = spriteTexel;
        return;
    }

    // Pulsating blend with the cell colour.
    float pulse = (sin(time * 6.2831) + 1.0) * 0.5;
    float blendFactor = mix(0.25, 0.75, pulse);

    vec3 blended = mix(spriteTexel.rgb, cellColour.rgb, blendFactor);
    float alpha = spriteTexel.a;

    gl_FragColor = vec4(blended, alpha);
}