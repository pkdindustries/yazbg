#version 330

//-----------------------------------------------------------------------------
// nearest_cell.fs – fragment shader that blends a sprite with the colour of
// the nearest occupied Tetris cell on the play-field.
//
// Uniform interface (all set from the CPU side):
//   texture0      – the sprite's diffuse texture (provided automatically by
//                   raylib when BeginShaderMode is active).
//   boardTex      –  a 10×20 RGBA texture that contains the current Tetris
//                    play-field.  Each texel corresponds to a single grid
//                    cell.  `boardTex.a == 0`  → empty cell.
//   gridSize      –  (10, 20) – integer width/height of the board.
//   cellSize      –  size of one cell in screen-space pixels ( floats ).
//   spritePos     –  top-left position of the sprite in screen-space pixels.
//   spriteSize    –  (w, h) size of the sprite in pixels.  In YazBG’s code-
//                    base sprites are squares, but the vector keeps it
//                    generic.
//   time          –  global time, enables pulsating effects.
//
// The shader samples `boardTex` at the grid cell nearest to the current
// fragment.  If that cell is occupied its colour is blended with the sprite
// colour in a nice pulse.  Otherwise the sprite is rendered normally.
//-----------------------------------------------------------------------------

// Attributes from the vertex shader ----------------------------------------------------
in vec2 fragTexCoord;
in vec4 fragColor;

// Uniforms -----------------------------------------------------------------------------
uniform sampler2D texture0;   // sprite texture (bound by rlgl)
uniform sampler2D boardTex;   // 10×20 grid texture holding cell colours

uniform vec2  gridSize;       // (10,20) in floats – cast to int in shader
uniform vec2  cellSize;       // pixels
uniform vec2  spritePos;      // top-left corner of the sprite (pixels)
uniform vec2  spriteSize;     // pixels (width,height)
uniform float time;           // seconds

uniform vec4  colDiffuse;     // global tint supplied by raylib

// Output ------------------------------------------------------------------------------
out vec4 finalColor;

//--------------------------------------------------------------------------------------
void main()
{
    // Fetch the sprite texel first.
    vec4 spriteTexel = texture(texture0, fragTexCoord)*fragColor*colDiffuse;

    // Compute the fragment’s world-space pixel position.
    vec2 worldPx = spritePos + fragTexCoord * spriteSize;

    // Determine the grid coordinate (integer cell) nearest to this pixel.
    ivec2 cellCoord = ivec2(floor(worldPx / cellSize));

    // Clamp to board area just in case the sprite overlaps the border.
    ivec2 gridLimits = ivec2(gridSize) - ivec2(1);
    cellCoord = clamp(cellCoord, ivec2(0), gridLimits);

    // Convert the integer cell coordinate into a UV for boardTex.
    vec2 boardUV = (vec2(cellCoord) + 0.5) / gridSize;
    vec4 cellColour = texture(boardTex, boardUV);

    // Early out: if the cell is empty keep original texel.
    if (cellColour.a < 0.01)
    {
        finalColor = spriteTexel;
        return;
    }

    // Otherwise generate a pleasant pulsating blend with the cell colour.
    float pulse = (sin(time*6.2831) + 1.0)*0.5;      // 0→1 every second
    float blendFactor = mix(0.25, 0.75, pulse);      // 0.25..0.75

    vec3 blended = mix(spriteTexel.rgb, cellColour.rgb, blendFactor);
    float alpha   = spriteTexel.a;                   // preserve sprite alpha

    finalColor = vec4(blended, alpha);
}
