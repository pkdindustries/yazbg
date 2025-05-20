#version 100
precision mediump float;

// Input vertex attributes (from vertex shader)
varying vec2 fragTexCoord;
varying vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform float time;
uniform float frequency;
uniform float intensity;

void main() {
    // Pulse effect parameters
    float freq = frequency;
    float intens = intensity;

    // Calculate pulse effect based on time
    float pulse = (sin(time * freq) + 1.0) * 0.5 * intens;

    // Sample the texture
    vec4 texelColor = texture2D(texture0, fragTexCoord);

    // Create a color that pulses between white and a vibrant color
    vec3 pulseColor = mix(vec3(1.0), vec3(0.2, 0.6, 1.0), pulse);

    // Final color: pulse color with original alpha, tinted by fragment color
    vec4 finalColor = vec4(pulseColor, texelColor.a) * fragColor * colDiffuse;
    gl_FragColor = finalColor;
}