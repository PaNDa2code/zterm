Texture2D glyphTexture : register(t0);
SamplerState texSampler : register(s0);

float4 main(float2 uv : TEXCOORD) : SV_Target
{
    float alpha = glyphTexture.Sample(texSampler, uv).r;
    return float4(1.0, 1.0, 1.0, alpha);
}
