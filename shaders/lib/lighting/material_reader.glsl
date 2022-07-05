vec3 GetLabPbr_Normal(const in vec2 normalXY) {
    return RestoreNormalZ(normalXY);
}

float GetLabPbr_F0(const in float specularG) {
    return specularG * step(specularG, 0.9);
}

int GetLabPbr_HCM(const in float specularG) {
    return int(floor(specularG * 255.0 - 229.5));
}

float GetLabPbr_SSS(const in float specularB) {
    return max(specularB - 0.25, 0.0) * (1.0 / 0.75);
}

float GetLabPbr_Porosity(const in float specularB) {
    return specularB * 4.0 * step(specularB, 0.25);
}

float GetLabPbr_Emission(const in float specularA) {
    return specularA * step(specularA, 1.0 - EPSILON);
}

#ifdef RENDER_DEFERRED
    PbrMaterial PopulateMaterial(const in vec3 colorMap, const in vec4 normalMap, const in vec4 specularMap) {
        PbrMaterial material;
        material.albedo.rgb = RGBToLinear(colorMap);
        material.normal = GetLabPbr_Normal(normalMap.xy);
        material.occlusion = normalMap.z;
        material.smoothness = specularMap.r;
        material.f0 = GetLabPbr_F0(specularMap.g);
        material.hcm = GetLabPbr_HCM(specularMap.g);
        material.porosity = GetLabPbr_Porosity(specularMap.b);
        material.scattering = GetLabPbr_SSS(specularMap.b);
        material.emission = GetLabPbr_Emission(specularMap.a);

        if (material.f0 < EPSILON) material.f0 = 0.04;
        material.albedo.a = 1.0;

        return material;
    }
#elif defined RENDER_WATER
    void PopulateMaterial(const in vec2 atlasCoord, out PbrMaterial material) {
    	vec4 colorMap = texture2D(gtexture, atlasCoord) * glcolor;
    	vec4 normalMap = texture2D(normals, atlasCoord);
    	vec4 specularMap = texture2D(specular, atlasCoord);

    	material.albedo.rgb = RGBToLinear(colorMap.rgb);
    	material.albedo.a = colorMap.a;

        if (material.normal.x < EPSILON && material.normal.y < EPSILON)
            material.normal = vec3(0.0, 0.0, 1.0);
        else {
            material.normal = GetLabPbr_Normal(normalMap.xy);
        }

    	material.occlusion = normalMap.b;
    	material.smoothness = specularMap.r;
    	material.f0 = GetLabPbr_F0(specularMap.g);
        material.hcm = GetLabPbr_HCM(specularMap.g);
    	material.porosity = GetLabPbr_Porosity(specularMap.b);
    	material.scattering = GetLabPbr_SSS(specularMap.b);
    	material.emission = GetLabPbr_Emission(specularMap.a);

    	if (material.f0 < EPSILON) material.f0 = 0.04;
    }
#endif
