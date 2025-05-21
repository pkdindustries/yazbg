#version 100
precision mediump float;

// Input vertex attributes (from vertex shader)
varying vec2 fragTexCoord;
varying vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Time uniform for static effect
uniform float time;

// Random generator for static noise
float random(vec2 coord) {
    return fract(sin(dot(coord, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    // Sample the texture color.
    vec4 texColor = texture2D(texture0, fragTexCoord);

    // Modulate the texture color.
    texColor *= colDiffuse * fragColor;

    // Apply static effect on non-transparent pixels.
    if (texColor.a > 0.0) {
        float randomValue = random(fragTexCoord * time);
        vec4 staticColor = vec4(randomValue, randomValue, randomValue, 1.0);
        vec4 finalColor = mix(texColor, staticColor, 0.4);
        gl_FragColor = finalColor;
    } else {
        gl_FragColor = texColor;
    }
}