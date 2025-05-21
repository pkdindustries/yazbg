#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform float time;
uniform float frequency;
uniform float intensity;

// Output fragment color
out vec4 finalColor;

void main()
{
    // Pulse effect parameters (can be customized per entity)
    float freq = frequency;   // Frequency of the pulse
    float intens = intensity; // Intensity of the pulse
    
    // Calculate pulse effect based on time - more dramatic swing
    float pulse = (sin(time * freq) + 1.0) * 0.5 * intens;
    
    // Sample the texture
    vec4 texelColor = texture(texture0, fragTexCoord);
    
    // Create a color that pulses between white and a vibrant color
    vec3 pulseColor = mix(vec3(1.0, 1.0, 1.0), vec3(0.2, 0.6, 1.0), pulse);
    
    // Final color: pulse color with original alpha, tinted by fragment color
    finalColor = vec4(pulseColor, texelColor.a) * fragColor * colDiffuse;
}