//
//  Shaders.metal
//  AugmentKit2
//
//  MIT License
//
//  Copyright (c) 2017 JamieScanlon
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//
//
//  Shaders that render anchors in 3D space.
//
// References --
// See: https://developer.apple.com/documentation/metal/advanced_techniques/lod_with_function_specialization#//apple_ref/doc/uid/TP40016233
// Sample Code: LODwithFunctionSpecialization
//
// See: https://developer.apple.com/videos/play/wwdc2017/610/
// Sample Code: ModelIO-from-MDLAsset-to-Game-Engine

#include <metal_stdlib>
#include <simd/simd.h>

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "../ShaderTypes.h"

using namespace metal;

// MARK: - Constants

constant bool has_base_color_map [[ function_constant(kFunctionConstantBaseColorMapIndex) ]];
constant bool has_normal_map [[ function_constant(kFunctionConstantNormalMapIndex) ]];
constant bool has_metallic_map [[ function_constant(kFunctionConstantMetallicMapIndex) ]];
constant bool has_roughness_map [[ function_constant(kFunctionConstantRoughnessMapIndex) ]];
constant bool has_ambient_occlusion_map [[ function_constant(kFunctionConstantAmbientOcclusionMapIndex) ]];
constant bool has_irradiance_map [[ function_constant(kFunctionConstantIrradianceMapIndex) ]];
constant bool has_any_map = has_base_color_map || has_normal_map || has_metallic_map || has_roughness_map || has_ambient_occlusion_map || has_irradiance_map;

constant float PI = 3.1415926535897932384626433832795;

// MARK: - Structs

// MARK: Ancors Vertex In
// Per-vertex inputs fed by vertex buffer laid out with MTLVertexDescriptor in Metal API
struct Vertex {
    float3 position      [[attribute(kVertexAttributePosition)]];
    float2 texCoord      [[attribute(kVertexAttributeTexcoord)]];
    float3 normal        [[attribute(kVertexAttributeNormal)]];
    ushort4 jointIndices [[attribute(kVertexAttributeJointIndices)]];
    float4 jointWeights  [[attribute(kVertexAttributeJointWeights)]];
};

// MARK: Ancors Vertex Out / Fragment In
// Vertex shader outputs and per-fragmeht inputs.  Includes clip-space position and vertex outputs
//  interpolated by rasterizer and fed to each fragment genterated by clip-space primitives.
struct ColorInOut {
    float4 position [[position]];
    float3 eyePosition;
    float3 normal;
    float2 texCoord [[ function_constant(has_any_map) ]];
//    float3 tangent;
//    float3 bitangent;
};

// MARK: - Pipeline Functions

// MARK: Lighting Parameters

struct LightingParameters {
    float3  lightDir;
    float3  lightCol;
    float3  viewDir;
    float3  halfVector;
    float3  reflectedVector;
    float3  normal;
    float3  reflectedColor;
    float3  irradiatedColor;
    float3  ambientOcclusion;
    float4  baseColor;
    float   nDoth;
    float   nDotv;
    float   nDotl;
    float   hDotl;
    float   metalness;
    float   roughness;
};

constexpr sampler linearSampler (mip_filter::linear,
                                 mag_filter::linear,
                                 address::repeat,
                                 min_filter::linear);

constexpr sampler nearestSampler(min_filter::linear, mag_filter::linear, mip_filter::none, address::repeat);

constexpr sampler mipSampler(address::clamp_to_edge, min_filter::linear, mag_filter::linear, mip_filter::linear);

LightingParameters calculateParameters(ColorInOut in,
                                       constant SharedUniforms & uniforms,
                                       constant MaterialUniforms & materialUniforms,
                                       texture2d<float> baseColorMap [[ function_constant(has_base_color_map) ]],
                                       texture2d<float> normalMap [[ function_constant(has_normal_map) ]],
                                       texture2d<float> metallicMap [[ function_constant(has_metallic_map) ]],
                                       texture2d<float> roughnessMap [[ function_constant(has_roughness_map) ]],
                                       texture2d<float> ambientOcclusionMap [[ function_constant(has_ambient_occlusion_map) ]],
                                       texturecube<float> irradianceMap [[ function_constant(has_irradiance_map) ]]);
inline float Fresnel(float dotProduct);
inline float sqr(float a);
float3 computeSpecular(LightingParameters parameters);
float Geometry(float Ndotv, float alphaG);
float3 computeNormalMap(ColorInOut in, texture2d<float> normalMapTexture);
float3 computeDiffuse(LightingParameters parameters);
float Distribution(float NdotH, float roughness);

inline float Fresnel(float dotProduct) {
    return pow(clamp(1.0 - dotProduct, 0.0, 1.0), 5.0);
}

inline float sqr(float a) {
    return a * a;
}

float Geometry(float Ndotv, float alphaG) {
    float a = alphaG * alphaG;
    float b = Ndotv * Ndotv;
    return (float)(1.0 / (Ndotv + sqrt(a + b - a*b)));
}

float3 computeNormalMap(ColorInOut in, texture2d<float> normalMapTexture) {
    float4 normalMap = float4((float4(normalMapTexture.sample(nearestSampler, float2(in.texCoord)).rgb, 0.0)));
    return float3(normalize(in.normal * normalMap.z));
}

float3 computeDiffuse(LightingParameters parameters) {
    return parameters.lightCol * parameters.nDotl;
}

float Distribution(float NdotH, float roughness) {
    if (roughness >= 1.0)
        return 1.0 / PI;
    
    float roughnessSqr = pow(roughness, 2);
    
    float d = (NdotH * roughnessSqr - NdotH) * NdotH + 1;
    return roughnessSqr / (PI * d * d);
}

float3 computeSpecular(LightingParameters parameters) {
    float specularRoughness = parameters.roughness;
    specularRoughness = max(specularRoughness, 0.01f);
    specularRoughness = pow(specularRoughness, 3.0f);
    
    float Ds = Distribution(parameters.nDoth, specularRoughness);
    
    float alphaG = sqr(specularRoughness * 0.5 + 0.5);
    float Gs = Geometry(parameters.nDotl, alphaG) * Geometry(parameters.nDotv, alphaG);
    float brdf = Ds * Gs * parameters.nDotl;
    float3 specularOutput = (brdf * parameters.irradiatedColor * parameters.lightCol) * mix(float3(1.0f), parameters.baseColor.xyz, parameters.metalness);
    
    return specularOutput * parameters.ambientOcclusion;
}

LightingParameters calculateParameters(ColorInOut in,
                                       constant SharedUniforms & sharedUniforms,
                                       constant MaterialUniforms & materialUniforms,
                                       texture2d<float> baseColorMap [[ function_constant(has_base_color_map) ]],
                                       texture2d<float> normalMap [[ function_constant(has_normal_map) ]],
                                       texture2d<float> metallicMap [[ function_constant(has_metallic_map) ]],
                                       texture2d<float> roughnessMap [[ function_constant(has_roughness_map) ]],
                                       texture2d<float> ambientOcclusionMap [[ function_constant(has_ambient_occlusion_map) ]],
                                       texturecube<float> irradianceMap [[ function_constant(has_irradiance_map) ]]) {
    LightingParameters parameters;
    
    parameters.baseColor = has_base_color_map ? (baseColorMap.sample(linearSampler, in.texCoord.xy)) : materialUniforms.baseColor;
    parameters.normal = has_normal_map ? computeNormalMap(in, normalMap) : float3(in.normal);
    
    // TODO: ??? - not sure if this is correct. float3(in.eyePosition) or -float3(in.eyePosition) ?
    parameters.viewDir = float3(in.eyePosition);
    parameters.reflectedVector = reflect(-parameters.viewDir, parameters.normal);
    
    parameters.roughness = has_roughness_map ? max(roughnessMap.sample(linearSampler, in.texCoord.xy).x, 0.001f) : materialUniforms.roughness;
    parameters.metalness = has_metallic_map ? metallicMap.sample(linearSampler, in.texCoord.xy).x : materialUniforms.metalness;
    
    uint8_t mipLevel = parameters.roughness * irradianceMap.get_num_mip_levels();
    parameters.irradiatedColor = has_irradiance_map ? irradianceMap.sample(mipSampler, parameters.reflectedVector, level(mipLevel)).xyz : materialUniforms.irradiatedColor.xyz;
    parameters.ambientOcclusion = has_ambient_occlusion_map ? ambientOcclusionMap.sample(linearSampler, in.texCoord.xy).x : 1.0f;
    
    parameters.lightCol = sharedUniforms.directionalLightColor;
    parameters.lightDir = -sharedUniforms.directionalLightDirection;
    
    // Light falls off based on how closely aligned the surface normal is to the light direction.
    // This is the dot product of the light direction vector and vertex normal.
    // The smaller the angle between those two vectors, the higher this value,
    // and the stronger the diffuse lighting effect should be.
    parameters.nDotl = max(0.001f, saturate(dot(parameters.normal, parameters.lightDir)));
    
    // Calculate the halfway vector between the light direction and the direction they eye is looking
    parameters.halfVector = normalize(parameters.lightDir + parameters.viewDir);
    
    parameters.nDoth = max(0.001f,saturate(dot(parameters.normal, parameters.halfVector)));
    parameters.nDotv = max(0.001f,saturate(dot(parameters.normal, parameters.viewDir)));
    parameters.hDotl = max(0.001f,saturate(dot(parameters.lightDir, parameters.halfVector)));
    
    return parameters;
    
}

// MARK: - Anchor Shaders

// MARK: Anchor geometry vertex function
vertex ColorInOut anchorGeometryVertexTransform(Vertex in [[stage_in]],
                                                constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]],
                                                constant AnchorInstanceUniforms *anchorInstanceUniforms [[ buffer(kBufferIndexAnchorInstanceUniforms) ]],
                                                uint vid [[vertex_id]],
                                                ushort iid [[instance_id]]) {
    ColorInOut out;
    
    // Make position a float4 to perform 4x4 matrix math on it
    float4 position = float4(in.position, 1.0);
    
    // Get the anchor model's orientation in world space
    float4x4 modelMatrix = anchorInstanceUniforms[iid].modelMatrix;
    
    // Transform the model's orientation from world space to camera space.
    float4x4 modelViewMatrix = sharedUniforms.viewMatrix * modelMatrix;
    
    // Calculate the position of our vertex in clip space and output for clipping and rasterization
    out.position = sharedUniforms.projectionMatrix * modelViewMatrix * position;
    
    // Calculate the positon of our vertex in eye space
    out.eyePosition = float3((modelViewMatrix * position).xyz);
    
    // Rotate our normals to world coordinates
    float4 normal = modelMatrix * float4(in.normal.x, in.normal.y, in.normal.z, 0.0f);
    out.normal = normalize(float3(normal.xyz));
    
    // Pass along the texture coordinate of our vertex such which we'll use to sample from texture's
    //   in our fragment function, if we need it
    if (has_any_map) {
        out.texCoord = float2(in.texCoord.x, 1.0f - in.texCoord.y);
    }
    
    return out;
}

// MARK: Anchor geometry fragment function with materials

fragment float4 anchorGeometryFragmentLighting(ColorInOut in [[stage_in]],
                                               constant SharedUniforms &uniforms [[ buffer(kBufferIndexSharedUniforms) ]],
                                               constant MaterialUniforms &materialUniforms [[ buffer(kBufferIndexMaterialUniforms) ]],
                                               texture2d<float> baseColorMap [[ texture(kTextureIndexColor), function_constant(has_base_color_map) ]],
                                               texture2d<float> normalMap    [[ texture(kTextureIndexNormal), function_constant(has_normal_map) ]],
                                               texture2d<float> metallicMap  [[ texture(kTextureIndexMetallic), function_constant(has_metallic_map) ]],
                                               texture2d<float> roughnessMap  [[ texture(kTextureIndexRoughness), function_constant(has_roughness_map) ]],
                                               texture2d<float> ambientOcclusionMap  [[ texture(kTextureIndexAmbientOcclusion), function_constant(has_ambient_occlusion_map) ]],
                                               texturecube<float> irradianceMap [[texture(kTextureIndexIrradianceMap), function_constant(has_irradiance_map)]]
                                               ) {
    
    float4 final_color = float4(0);
    
    LightingParameters parameters = calculateParameters(in,
                                                        uniforms,
                                                        materialUniforms,
                                                        baseColorMap,
                                                        normalMap,
                                                        metallicMap,
                                                        roughnessMap,
                                                        ambientOcclusionMap,
                                                        irradianceMap);
    
    // FIXME: discard_fragment may have performance implications.
    // see: http://metalbyexample.com/translucency-and-transparency/
    if ( parameters.baseColor.w <= 0.01f ) {
        discard_fragment();
    }
    
    // Compute the diffuse and spectacular contributions
    
    float3 diffuseContribution = computeDiffuse(parameters);
    float3 specularContribution = computeSpecular(parameters);
    
    // The ambient contribution, which is an approximation for global, indirect lighting, is
    // the product of the ambient light intensity multiplied by the ambient light color
    // (assumed as <0.5, 0.5, 0.5> by the renderer)
    float3 ambientContribution = uniforms.ambientLightColor;

    // Now that we have the contributions our light sources in the scene, we sum them together
    // to get the fragment's lighting value
    float3 lightContributions = diffuseContribution + specularContribution + ambientContribution;
    
    // We compute the final color by multiplying the base color with all of the environmental contributions
    final_color = float4(parameters.baseColor.rgb * lightContributions, 1.0f);
    
    return final_color;
    
}

