
#include <metal_stdlib>

using namespace metal;

struct ImageVertex {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct TexturedQuadVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct FrameUniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
};

struct FragmentUniforms {
    float3 ambientLightColor;
    float3 directionalLightDirection;
    float3 directionalLightColor;
    float materialShininess;
};

struct InstanceUniforms {
    float4x4 modelMatrix;
};

vertex TexturedQuadVertexOut cameraVertexTransform(ImageVertex in [[stage_in]]) {
    TexturedQuadVertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 cameraFragmentShader(TexturedQuadVertexOut in [[stage_in]],
                                            texture2d<float, access::sample> cameraTextureY [[ texture(1) ]],
                                            texture2d<float, access::sample> cameraTextureCbCr [[ texture(2) ]])
{
    
    constexpr sampler colorSampler(filter::linear);
    
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4( 1.0000f,  1.0000f,  1.0000f, 0.0000f),
        float4( 0.0000f, -0.3441f,  1.7720f, 0.0000f),
        float4( 1.4020f, -0.7141f,  0.0000f, 0.0000f),
        float4(-0.7010f,  0.5291f, -0.8860f, 1.0000f)
    );

    float4 ycbcr = float4(cameraTextureY.sample(colorSampler, in.texCoord).r,
                          cameraTextureCbCr.sample(colorSampler, in.texCoord).rg, 1.0);
    return ycbcrToRGBTransform * ycbcr;
}

struct Vertex {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float4 color2;
    float3 eyePosition;
    float3 normal;
};


vertex VertexOut anchorGeometryVertexTransform(Vertex in [[stage_in]],
                                                constant FrameUniforms &uniforms [[ buffer(3) ]],
                                                constant InstanceUniforms *instanceUniforms [[ buffer(2) ]],
                                                constant uint *inBox [[ buffer(4) ]],
                                                ushort vid [[vertex_id]],
                                                ushort iid [[instance_id]]) {
    VertexOut out;

    float4 position = float4(in.position, 1.0);
    
    float4x4 modelMatrix = instanceUniforms[iid].modelMatrix;
    float4x4 modelViewMatrix = uniforms.viewMatrix * modelMatrix;
    out.position = uniforms.projectionMatrix * modelViewMatrix * position;
    
    out.eyePosition = (modelViewMatrix * position).xyz;

    float4 normal = modelMatrix * float4(in.normal.xyz, 0.0f);
    out.normal = normalize(normal.xyz);
    
    
    if (inBox[vid] == 1)
    {
        out.color = float4(0.2, 0.28, 0.85, 0.45f);
        out.color2 = float4(1.0f);
    }
    else
    {
        out.color = float4(0.0, 0.0, 0.0, 0.0f);
        out.color2 = float4(0.0f);
    }
    
    return out;
}


fragment float4 anchorGeometryFragmentLighting(VertexOut in [[stage_in]],
                                               texture2d<float, access::sample> colorMap [[texture(0)]])
{
    return in.color;
}


fragment float4 geometryOutlineFragment(VertexOut in [[stage_in]])
{
    return in.color2;
}
