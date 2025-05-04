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
    
    // Calculate pulse effect based on time
    float pulse = (sin(time * freq) + 1.0) * 0.5 * intens;
    
    // Sample the texture
    vec4 texelColor = texture(texture0, fragTexCoord);
    
    // Apply pulse effect by brightening the texture
    vec4 pulseColor = texelColor * (1.0 + pulse);
    
    // Final color: adjusted by pulse and tinted by fragment color
    finalColor = pulseColor * fragColor * colDiffuse;
}