#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Output fragment color
out vec4 finalColor;

uniform float time;

float random(vec2 coord) {
    return fract(sin(dot(coord.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    // Sample the texture color.
    vec4 texColor = texture(texture0, fragTexCoord);

    // Modulate the texture color.
    texColor *= colDiffuse * fragColor;

    // Check if the pixel is not transparent.
    if (texColor.a > 0.0) {
        // Generating a random value for the static effect.
        float randomValue = random(fragTexCoord * time);

        // Creating a grayscale color for the static effect.
        vec4 staticColor = vec4(randomValue, randomValue, randomValue, 1.0);

        // Blending the static effect with the modulated texture color.
        finalColor = mix(texColor, staticColor, 0.4);
    } else {
        // For transparent pixels, just use the original texture color.
        finalColor = texColor;
    }
}
