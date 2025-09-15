#version 300 es
precision mediump float;

in vec2 fragTexCoord;
in vec3 normal;
in vec4 color;

uniform sampler2D texture0;
uniform vec4 colDiffuse;
uniform vec3 sunDirection;

out vec4 fragOutput;

const float _Cutoff            = 0.5;  // альфа-отсечка
const float _MinimalLightLevel = 0.35;  // минимальный уровень освещённости

void main() {
    vec4 col = texture(texture0, fragTexCoord);

    // --- AO / shadow
    float shadow = clamp(color.r + 0.1, 0.0, 1.0);

    col.rgb *= shadow;

    // --- Alpha cutoff
    float diff = col.a - _Cutoff;
    if (diff < 0.0) discard;

    // --- Sun lighting + bounce
    vec3 n   = normalize(normal);
    vec3 sun = normalize(sunDirection);

    float brightness = max(0.0, dot(n, sun));
    float bounced    = (1.0 - max(0.0, dot(n, -sun))) * 0.2;
    brightness = max(_MinimalLightLevel, min(1.0, brightness + bounced));

    col.rgb *= brightness;

    // --- Diffuse multiplier
    col *= colDiffuse;

    fragOutput = col;
}
