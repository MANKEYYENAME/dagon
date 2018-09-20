#version 400 core

uniform int layer;
uniform float blurMask;

in vec2 texCoord;
in vec3 eyePosition;
in vec3 eyeNormal;

in vec4 blurPosition;
in vec4 prevPosition;

vec3 toLinear(vec3 v)
{
    return pow(v, vec3(2.2));
}


/*
 * Diffuse color subroutines.
 * Used to switch color/texture.
 */
subroutine vec4 srtColor(in vec2 uv);

uniform vec4 diffuseVector;
subroutine(srtColor) vec4 diffuseColorValue(in vec2 uv)
{
    return diffuseVector;
}

uniform sampler2D diffuseTexture;
subroutine(srtColor) vec4 diffuseColorTexture(in vec2 uv)
{
    return texture(diffuseTexture, uv);
}

subroutine uniform srtColor diffuse;


/*
 * Normal mapping subroutines.
 */
subroutine vec3 srtNormal(in vec2 uv, in float ysign, in mat3 tangentToEye);

mat3 cotangentFrame(in vec3 N, in vec3 p, in vec2 uv)
{
    vec3 dp1 = dFdx(p);
    vec3 dp2 = dFdy(p);
    vec2 duv1 = dFdx(uv);
    vec2 duv2 = dFdy(uv);
    vec3 dp2perp = cross(dp2, N);
    vec3 dp1perp = cross(N, dp1);
    vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
    float invmax = inversesqrt(max(dot(T, T), dot(B, B)));
    return mat3(T * invmax, B * invmax, N);
}

uniform vec3 normalVector;
subroutine(srtNormal) vec3 normalValue(in vec2 uv, in float ysign, in mat3 tangentToEye)
{            
    vec3 tN = normalVector;
    tN.y *= ysign;
    return normalize(tangentToEye * tN);
}

uniform sampler2D normalTexture;
subroutine(srtNormal) vec3 normalMap(in vec2 uv, in float ysign, in mat3 tangentToEye)
{            
    vec3 tN = normalize(texture(normalTexture, uv).rgb * 2.0 - 1.0);
    tN.y *= ysign;
    return normalize(tangentToEye * tN);
}

subroutine uniform srtNormal normal;


/*
 * Height mapping subroutines.
 */
subroutine float srtHeight(in vec2 uv);

uniform float heightScalar;
subroutine(srtHeight) float heightValue(in vec2 uv)
{            
    return heightScalar;
}

subroutine(srtHeight) float heightMap(in vec2 uv)
{            
    return texture(normalTexture, uv).a;
}

subroutine uniform srtHeight height;


/*
 * Parallax mapping
 */
uniform float parallaxScale;
uniform float parallaxBias;
vec2 parallaxMapping(in vec3 E, in vec2 uv, in float height)
{
    float h = height * parallaxScale + parallaxBias;
    return uv + (h * E.xy);
}


/*
 * PBR parameters
 */
uniform sampler2D pbrTexture;

/*
 * Emission
 */
subroutine vec4 srtEmission(in vec2 uv);

uniform vec4 emissionVector;
subroutine(srtEmission) vec4 emissionValue(in vec2 uv)
{            
    return emissionVector;
}

uniform sampler2D emissionTexture;
subroutine(srtEmission) vec4 emissionMap(in vec2 uv)
{            
    return texture(emissionTexture, uv);
}

subroutine uniform srtEmission emission;

uniform float emissionEnergy;

layout(location = 0) out vec4 frag_color;
layout(location = 1) out vec4 frag_rms;
layout(location = 2) out vec4 frag_position;
layout(location = 3) out vec4 frag_normal;
layout(location = 4) out vec4 frag_velocity;
layout(location = 5) out vec4 frag_emission;

void main()
{
    vec3 E = normalize(-eyePosition);
    vec3 N = normalize(eyeNormal);

    mat3 tangentToEye = cotangentFrame(N, eyePosition, texCoord);
    vec3 tE = normalize(E * tangentToEye);
    
    vec2 posScreen = (blurPosition.xy / blurPosition.w) * 0.5 + 0.5;
    vec2 prevPosScreen = (prevPosition.xy / prevPosition.w) * 0.5 + 0.5;
    vec2 screenVelocity = posScreen - prevPosScreen;

    // TODO: parallax occlusion mapping
    vec2 shiftedTexCoord = parallaxMapping(tE, texCoord, height(texCoord));
    
    N = normal(shiftedTexCoord, -1.0, tangentToEye);
    
    vec4 diffuseColor = diffuse(shiftedTexCoord);
    
    vec4 rms = texture(pbrTexture, shiftedTexCoord);
    vec3 emiss = emission(shiftedTexCoord).rgb * emissionEnergy;
    
    float geomMask = float(layer > 0);
    
    frag_color = vec4(diffuseColor.rgb, geomMask);
    frag_rms = vec4(rms.r, rms.g, 1.0, 1.0);
    frag_position = vec4(eyePosition, geomMask);
    frag_normal = vec4(N, 1.0);
    frag_velocity = vec4(screenVelocity, 0.0, blurMask);
    frag_emission = vec4(emiss, 1.0);
}
