#version 100
precision mediump float;

// Input vertex attributes (from vertex shader)
varying vec2 fragTexCoord;
varying vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Time uniform for glitch effect
uniform float time;

// Random generator for glitch effect
float random(float seed) {
    return fract(sin(seed) * 43758.5453123);
}

void main() {
    vec2 uv = fragTexCoord;
    
    // Time-varying value for controlling the glitch effect
    float t = time * 10.0;
    
    // Create horizontal glitch lines
    float blockLine = floor(uv.y * 32.0);
    float jitter = random(blockLine + t) * 2.0 - 1.0;
    
    // Intensity of the effect based on random values
    float glitchIntensity = random(t * 0.1) * 0.1;
    
    // Apply horizontal displacement
    uv.x += jitter * glitchIntensity;
    
    // Add color channel shifting for some blocks
    float lineIntensity = step(0.8, random(blockLine * t));
    if (lineIntensity > 0.5 && random(blockLine) > 0.75) {
        // RGB channel separation
        float redShift = random(blockLine + t * 0.3) * 0.02;
        float blueShift = random(blockLine + t * 0.5) * 0.02;
        
        vec4 redChannel = texture2D(texture0, vec2(uv.x + redShift, uv.y));
        vec4 greenChannel = texture2D(texture0, uv);
        vec4 blueChannel = texture2D(texture0, vec2(uv.x - blueShift, uv.y));
        
        // Sample the texture color with offset channels
        vec4 texColor = vec4(redChannel.r, greenChannel.g, blueChannel.b, greenChannel.a);
        
        // Modulate the texture color
        texColor *= colDiffuse * fragColor;
        gl_FragColor = texColor;
    } else {
        // Sample the texture color
        vec4 texColor = texture2D(texture0, uv);
        
        // Modulate the texture color
        texColor *= colDiffuse * fragColor;
        gl_FragColor = texColor;
    }
}