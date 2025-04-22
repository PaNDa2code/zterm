cbuffer ConstantBuffer : register(b0)
{
    matrix modelViewProj;
};

struct VS_INPUT {
    float3 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

struct VS_OUTPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};

VS_OUTPUT main(VS_INPUT input)
{
    VS_OUTPUT output;
    output.pos = mul(modelViewProj, float4(input.pos, 1.0f));
    output.uv = input.uv;
    return output;
}
