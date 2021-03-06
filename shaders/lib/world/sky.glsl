const float[5] moonPhaseLevels = float[](0.08, 0.25, 0.50, 0.75, 1.0);

float GetSolidAngle(const in float angularDiameter) {
    return 2.0 * PI * (1.0 - cos(0.5 * angularDiameter * PI * 180.0));
}

// returns: x:sun y:moon
vec2 GetSkyLightLevels() {
    vec3 upDir = normalize(upPosition);
    vec3 sunLightDir = normalize(sunPosition);
    vec3 moonLightDir = normalize(moonPosition);

    return vec2(
        dot(upDir, sunLightDir),
        dot(upDir, moonLightDir));
}

float GetSunLightLevel(const in float skyLightLevel) {
    //float rainLevel = 1.0 - 0.85 * rainStrength;

    //float angularDiameter = mix(0.526, 0.545, max(skyLightLevel, 0.0));
    //return GetSolidAngle(angularDiameter);

    // TODO: This angle is wrong and sucks
    return pow(max(skyLightLevel, 0.0), 0.4);
}

float GetMoonLightLevel(const in float skyLightLevel) {
    //float rainLevel = 1.0 - 0.9 * rainStrength;
    float moonPhaseLevel = moonPhaseLevels[abs(moonPhase-4)];

    //float angularDiameter = mix(0.49, 0.55, max(skyLightLevel, 0.0));
    //return GetSolidAngle(angularDiameter) * moonPhaseLevel;

    // TODO: This angle is wrong and sucks
    return pow(max(skyLightLevel, 0.0), 0.4) * moonPhaseLevel;
}

// returns: x:sun y:moon temp in kelvin
vec2 GetSkyLightTemp(const in vec2 skyLightLevels) {
    const float temp_sunrise = 2200; // 2000
    const float temp_day = 5000; // 5000
    const float temp_rain = 7800; // 8000
    const float temp_moon = 4100; // 5500

    float sunTemp = mix(temp_sunrise, temp_day, max(skyLightLevels.x, 0.0));
    sunTemp = mix(sunTemp, temp_rain, rainStrength);

    return vec2(sunTemp, temp_moon);
}

vec3 GetSunLightColor(const in float temp, const in float skyLightLevel) {
    return blackbody(temp) * GetSunLightLevel(skyLightLevel);
}

vec3 GetMoonLightColor(const in float temp, const in float skyLightLevel) {
    return blackbody(temp) * GetMoonLightLevel(skyLightLevel);
}

float GetSunLightLux(const in float skyLightLevel) {
    float lux = mix(SunLux, SunOvercastLux, rainStrength);
    return GetSunLightLevel(skyLightLevel) * lux;
}

vec3 GetSunLightLuxColor(const in float temp, const in float skyLightLevel) {
    float lux = mix(SunLux, SunOvercastLux, rainStrength);
    return GetSunLightColor(temp, skyLightLevel) * lux;
}

float GetMoonLightLux(const in float skyLightLevel) {
    float lux = mix(MoonLux, MoonOvercastLux, rainStrength);
    return GetSunLightLevel(skyLightLevel) * lux;
}

vec3 GetMoonLightLuxColor(const in float temp, const in float skyLightLevel) {
    float lux = mix(MoonLux, MoonOvercastLux, rainStrength);
    return GetSunLightColor(temp, skyLightLevel) * lux;
}

vec3 GetSkyLightLuminance(const in vec2 skyLightLevels) {
    //vec2 skyLightLevels = GetSkyLightLevels();
    vec2 skyLightTemp = GetSkyLightTemp(skyLightLevels);

    vec3 sunLum = GetSunLightLuxColor(skyLightTemp.x, skyLightLevels.x);
    vec3 moonLum = GetMoonLightLuxColor(skyLightTemp.y, skyLightLevels.y);

    return sunLum + moonLum;
}

#ifdef RENDER_FRAG
    float GetVanillaSkyFog(const in float x, const in float w) {
        return w / (x * x + w);
    }

    vec3 GetVanillaSkyLuminance(const in vec3 viewDir) {
        vec2 skyLightLevels = GetSkyLightLevels();
        float sunSkyLumen = GetSunLightLevel(skyLightLevels.x) * mix(DaySkyLumen, DaySkyOvercastLumen, rainStrength);
        float moonSkyLumen = GetMoonLightLevel(skyLightLevels.y) * mix(NightSkyLumen, NightSkyOvercastLumen, rainStrength);
        float skyLumen = sunSkyLumen + moonSkyLumen;

        vec3 skyColorLinear = RGBToLinear(skyColor) * skyLumen;
        vec3 fogColorLinear = RGBToLinear(fogColor) * skyLumen;

        #ifdef RENDER_SKYBASIC
            if (isEyeInWater == 1) {
                // TODO: change fogColor to water
                fogColorLinear = vec3(0.0178, 0.0566, 0.0754) * skyLumen;
            }
        #endif

        fogColorLinear = mix(fogColorLinear, vec3(0.839, 0.843, 0.824) * skyLumen, rainStrength);

        vec3 upDir = normalize(upPosition);
        float VoUm = max(dot(viewDir, upDir), 0.0);
        float skyFogFactor = GetVanillaSkyFog(VoUm, 0.25);
        return mix(skyColorLinear, fogColorLinear, skyFogFactor);
    }

    vec3 GetVanillaSkyLux(const in vec3 viewDir) {
        vec2 skyLightLevels = GetSkyLightLevels();
        float sunLightLux = GetSunLightLux(skyLightLevels.x);
        float moonLightLux = GetMoonLightLux(skyLightLevels.y);
        float skyLux = sunLightLux + moonLightLux;

        vec3 skyColorLinear = RGBToLinear(skyColor) * skyLux;
        vec3 fogColorLinear = RGBToLinear(fogColor) * skyLux;

        vec3 upDir = normalize(upPosition);
        float VoUm = max(dot(viewDir, upDir), 0.0);
        float skyFogFactor = GetVanillaSkyFog(VoUm, 0.25);
        return mix(skyColorLinear, fogColorLinear, skyFogFactor);
    }

    vec3 GetVanillaSkyScattering(const in vec3 viewDir, const in vec3 sunColor, const in vec3 moonColor) {
        float G_scattering = mix(G_SCATTERING_CLEAR, G_SCATTERING_RAIN, rainStrength);

        vec3 sunDir = normalize(sunPosition);
        float sun_VoL = dot(viewDir, sunDir);
        float sunScattering = ComputeVolumetricScattering(sun_VoL, G_scattering);

        vec3 moonDir = normalize(moonPosition);
        float moon_VoL = dot(viewDir, moonDir);
        float moonScattering = ComputeVolumetricScattering(moon_VoL, G_scattering);

        return sunScattering * sunColor + moonScattering * moonColor;
    }
#endif
