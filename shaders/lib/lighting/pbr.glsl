#ifdef RENDER_VERTEX
    void PbrVertex(const in mat3 matViewTBN) {//, const in vec3 viewPos) {
        tanViewPos = matViewTBN * viewPos;

        #ifdef PARALLAX_ENABLED
            vec2 coordMid = (gl_TextureMatrix[0] * mc_midTexCoord).xy;
            vec2 coordNMid = texcoord - coordMid;

            atlasBounds[0] = min(texcoord, coordMid - coordNMid);
            atlasBounds[1] = abs(coordNMid) * 2.0;
 
            localCoord = sign(coordNMid) * 0.5 + 0.5;
        #endif

        #if MATERIAL_FORMAT == MATERIAL_FORMAT_DEFAULT && (defined RENDER_TERRAIN || defined RENDER_WATER)
            ApplyHardCodedMaterials();
        #endif
    }
#endif

#ifdef RENDER_FRAG
    float F_schlick(const in float cos_theta, const in float f0, const in float f90) {
        float invCosTheta = saturate(1.0 - cos_theta);
        return f0 + (f90 - f0) * pow5(invCosTheta);
    }

    float SchlickRoughness(const in float f0, const in float cos_theta, const in float rough) {
        float invCosTheta = saturate(1.0 - cos_theta);
        return f0 + (max(1.0 - rough, f0) - f0) * pow5(invCosTheta);
    }

    vec3 F_conductor(const in float VoH, const in float n1, const in vec3 n2, const in vec3 k) {
        vec3 eta = n2 / n1;
        vec3 eta_k = k / n1;

        float cos_theta2 = pow2(VoH);
        float sin_theta2 = 1.0f - cos_theta2;
        vec3 eta2 = pow2(eta);
        vec3 eta_k2 = pow2(eta_k);

        vec3 t0 = eta2 - eta_k2 - sin_theta2;
        vec3 a2_plus_b2 = sqrt(t0 * t0 + 4.0f * eta2 * eta_k2);
        vec3 t1 = a2_plus_b2 + cos_theta2;
        vec3 a = sqrt(0.5f * (a2_plus_b2 + t0));
        vec3 t2 = 2.0f * a * VoH;
        vec3 rs = (t1 - t2) / (t1 + t2);

        vec3 t3 = cos_theta2 * a2_plus_b2 + sin_theta2 * sin_theta2;
        vec3 t4 = t2 * sin_theta2;
        vec3 rp = rs * (t3 - t4) / (t3 + t4);

        return 0.5f * (rp + rs);
    }

    float GGX(const in float NoH, const in float roughL) {
        float a = NoH * roughL;
        float k = roughL / (1.0 - pow2(NoH) + pow2(a));
        //return pow2(k) * invPI;
        return min(pow2(k) * invPI, 65504.0);
    }

    float GGX_Fast(const in float NoH, const in vec3 NxH, const in float roughL) {
        float a = NoH * roughL;
        float k = roughL / (dot(NxH, NxH) + pow2(a));
        return min(pow2(k) * invPI, 65504.0);
    }

    float SmithGGXCorrelated(const in float NoV, const in float NoL, const in float roughL) {
        float a2 = pow2(roughL);
        float GGXV = NoL * sqrt(max(NoV * NoV * (1.0 - a2) + a2, EPSILON));
        float GGXL = NoV * sqrt(max(NoL * NoL * (1.0 - a2) + a2, EPSILON));
        return saturate(0.5 / (GGXV + GGXL));
    }

    float SmithGGXCorrelated_Fast(const in float NoV, const in float NoL, const in float roughL) {
        float GGXV = NoL * (NoV * (1.0 - roughL) + roughL);
        float GGXL = NoV * (NoL * (1.0 - roughL) + roughL);
        return saturate(0.5 / (GGXV + GGXL));
    }

    float SmithHable(const in float LoH, const in float alpha) {
        return rcp(mix(pow2(LoH), 1.0, pow2(alpha) * 0.25));
    }

    vec3 GetFresnel(const in PbrMaterial material, const in float VoH, const in float roughL) {
        #if MATERIAL_FORMAT == MATERIAL_FORMAT_LABPBR || MATERIAL_FORMAT == MATERIAL_FORMAT_DEFAULT
            if (material.hcm >= 0) {
                vec3 iorN, iorK;
                GetHCM_IOR(material.albedo.rgb, material.hcm, iorN, iorK);
                return F_conductor(VoH, IOR_AIR, iorN, iorK);
            }
            else {
                return vec3(SchlickRoughness(material.f0, VoH, roughL));
            }
        #else
            float dielectric_F = 0.0;
            if (material.f0 + EPSILON < 1.0)
                dielectric_F = SchlickRoughness(0.04, VoH, roughL);

            vec3 conductor_F = vec3(0.0);
            if (material.f0 - EPSILON > 0.04) {
                vec3 iorN = vec3(f0ToIOR(material.albedo.rgb));
                vec3 iorK = material.albedo.rgb;

                conductor_F = min(F_conductor(VoH, IOR_AIR, iorN, iorK), 1000.0);
            }

            float metalF = saturate((material.f0 - 0.04) * (1.0/0.96));
            return mix(vec3(dielectric_F), conductor_F, metalF);
        #endif
    }

    vec3 GetSpecularBRDF(const in vec3 F, const in float NoV, const in float NoL, const in float NoH, const in float roughL)
    {
        // Fresnel
        //vec3 F = GetFresnel(material, VoH, roughL);

        // Distribution
        float D = GGX(NoH, roughL);

        // Geometric Visibility
        float G = SmithGGXCorrelated_Fast(NoV, NoL, roughL);

        //return clamp(D * F * G, 0.0, 100000.0);
        return D * F * G;
    }

    vec3 GetDiffuse_Burley(const in vec3 albedo, const in float NoV, const in float NoL, const in float LoH, const in float roughL) {
        float f90 = 0.5 + 2.0 * roughL * pow2(LoH);
        float light_scatter = F_schlick(NoL, 1.0, f90);
        float view_scatter = F_schlick(NoV, 1.0, f90);
        return (albedo * invPI) * light_scatter * view_scatter * NoL;
    }

    vec3 GetSubsurface(const in vec3 albedo, const in float NoV, const in float NoL, const in float LoH, const in float roughL) {
        float sssF90 = roughL * pow2(LoH);
        float sssF_In = F_schlick(NoV, 1.0, sssF90);
        float sssF_Out = F_schlick(NoL, 1.0, sssF90);

        return (1.25 * albedo * invPI) * (sssF_In * sssF_Out * (rcp(1.0 + (NoV + NoL)) - 0.5) + 0.5);// * NoL;
    }

    vec3 GetDiffuseBSDF(const in PbrMaterial material, const in float NoV, const in float NoL, const in float LoH, const in float roughL) {
        vec3 diffuse = GetDiffuse_Burley(material.albedo.rgb, NoV, NoL, LoH, roughL);

        #ifdef SSS_ENABLED
            if (material.scattering < EPSILON) return diffuse;

            vec3 subsurface = GetSubsurface(material.albedo.rgb, NoV, NoL, LoH, roughL);
            return (1.0 - material.scattering) * diffuse + material.scattering * subsurface;
        #else
            return diffuse;
        #endif
    }


    // Common Usage Pattern

    #ifdef HANDLIGHT_ENABLED
        float GetHandLightAttenuation(const in float lightLevel, const in float lightDist) {
            float diffuseAtt = max(0.0625*lightLevel - 0.08*lightDist, 0.0);
            return pow5(diffuseAtt);
        }

        void ApplyHandLighting(inout vec3 diffuse, inout vec3 specular, const in PbrMaterial material, const in vec3 viewNormal, const in vec3 viewPos, const in vec3 viewDir, const in float NoVm, const in float roughL) {
            vec3 lightPos = handOffset - viewPos.xyz;
            vec3 lightDir = normalize(lightPos);

            float NoLm = max(dot(viewNormal, lightDir), 0.0);
            if (NoLm < EPSILON) return;

            float lightDist = length(lightPos);
            float attenuation = GetHandLightAttenuation(heldBlockLightValue, lightDist);
            if (attenuation < EPSILON) return;

            vec3 halfDir = normalize(lightDir + viewDir);
            float LoHm = max(dot(lightDir, halfDir), EPSILON);
            float NoHm = max(dot(viewNormal, halfDir), EPSILON);
            float VoHm = max(dot(viewDir, halfDir), EPSILON);

            vec3 handLightColor = blockLightColor * attenuation;

            vec3 F = GetFresnel(material, VoHm, roughL);

            diffuse += GetDiffuseBSDF(material, NoVm, NoLm, LoHm, roughL) * handLightColor;
            specular += GetSpecularBRDF(F, NoVm, NoLm, NoHm, roughL) * handLightColor;
        }
    #endif

    #ifdef RENDER_WATER
        float GetWaterDepth(const in vec2 screenUV) {
            float waterViewDepthLinear = linearizeDepthFast(gl_FragCoord.z, near, far);
            if (isEyeInWater == 1) return waterViewDepthLinear;

            float solidViewDepth = textureLod(depthtex1, screenUV, 0).r;
            float solidViewDepthLinear = linearizeDepthFast(solidViewDepth, near, far);
            return max(solidViewDepthLinear - waterViewDepthLinear, 0.0);
        }

        // returns: x=water-depth, y=solid-depth
        vec2 GetWaterSolidDepth(const in vec2 screenUV) {
            float solidViewDepth = textureLod(depthtex1, screenUV, 0).r;
            float solidViewDepthLinear = linearizeDepthFast(solidViewDepth, near, far);
            float waterViewDepthLinear = linearizeDepthFast(gl_FragCoord.z, near, far);

            return vec2(waterViewDepthLinear, solidViewDepthLinear);
        }
    #endif

    vec3 GetSkyReflectionColor(const in vec3 reflectDir, const in vec3 viewNormal) {
        // darken lower horizon
        vec3 downDir = normalize(-upPosition);
        float RoDm = max(dot(reflectDir, downDir), 0.0);
        float reflectF = 1.0 - RoDm;

        // occlude inward reflections
        //float NoRm = max(dot(reflectDir, -viewNormal), 0.0);
        //reflectF *= 1.0 - pow(NoRm, 0.5);

        vec3 skyLumen = GetVanillaSkyLuminance(reflectDir);
        vec3 skyScatter = GetVanillaSkyScattering(reflectDir, sunColor, moonColor);

        //return (skyLumen + skyScatter) * reflectF;
        return skyLumen * reflectF;
    }

    vec4 PbrLighting2(const in PbrMaterial material, const in vec2 lmValue, const in float shadow, const in float shadowSSS, const in vec3 viewPos, const in vec2 waterSolidDepth) {
        vec2 viewSize = vec2(viewWidth, viewHeight);
        vec3 viewNormal = normalize(material.normal);
        vec3 viewDir = -normalize(viewPos.xyz);
        float viewDist = length(viewPos.xyz);

        vec2 screenUV = gl_FragCoord.xy / viewSize;

        //return vec4((material.normal * 0.5 + 0.5) * 500.0, 1.0);

        #ifdef SHADOW_ENABLED
            vec3 viewLightDir = normalize(shadowLightPosition);
            float NoL = dot(viewNormal, viewLightDir);

            vec3 halfDir = normalize(viewLightDir + viewDir);
            float LoHm = max(dot(viewLightDir, halfDir), 0.0);
        #else
            float NoL = 1.0;
            float LoHm = 1.0;
        #endif

        float NoLm = max(NoL, 0.0);
        float NoVm = max(dot(viewNormal, viewDir), 0.0);

        float rough = 1.0 - material.smoothness;
        float roughL = max(rough * rough, 0.005);

        float blockLight = saturate((lmValue.x - (0.5/16.0)) / (15.0/16.0));
        float skyLight = saturate((lmValue.y - (0.5/16.0)) / (15.0/16.0));

        #ifdef SHADOW_ENABLED
            // Increase skylight when in direct sunlight
            //skyLight = max(skyLight, shadow);
        #endif

        // Make areas without skylight fully shadowed (light leak fix)
        float lightLeakFix = step(1.0 / 32.0, skyLight);
        float shadowFinal = shadow * lightLeakFix;

        float skyLight3 = pow3(skyLight);

        //float reflectF = 0.0;
        vec3 reflectColor = vec3(0.0);
        #if REFLECTION_MODE != REFLECTION_MODE_NONE
            if (material.smoothness > EPSILON) {
                vec3 reflectDir = reflect(-viewDir, viewNormal);

                #if REFLECTION_MODE == REFLECTION_MODE_SCREEN
                    // vec2 reflectionUV;
                    // float atten = GetReflectColor(texcoord, depth, viewPos, reflectDir, reflectionUV);

                    // if (atten > EPSILON) {
                    //     ivec2 iReflectUV = ivec2(reflectionUV * 0.5 * vec2(viewWidth, viewHeight));
                    //     reflectColor = texelFetch(BUFFER_HDR_PREVIOUS, iReflectUV, 0) / max(exposure, EPSILON);
                    // }

                    // if (atten + EPSILON < 1.0) {
                    //     vec3 skyColor = GetVanillaSkyLux(reflectDir);
                    //     reflectColor = mix(skyColor, reflectColor, atten);
                    // }

                    vec4 roughReflectColor = RoughReflection(depthtex1, viewPos, reflectDir, rough, 0.0);
                    reflectColor = roughReflectColor.rgb * roughReflectColor.a;

                    if (roughReflectColor.a < 1.0 - EPSILON) {
                        vec3 skyReflectColor = GetSkyReflectionColor(reflectDir, viewNormal) * skyLight;
                        reflectColor += skyReflectColor * (1.0 - roughReflectColor.a);
                    }

                    //return vec4(reflectColor, 1.0);

                #elif REFLECTION_MODE == REFLECTION_MODE_SKY
                    reflectColor = GetSkyReflectionColor(reflectDir, viewNormal) * skyLight;
                #endif
            }
        #endif

        //return vec4(reflectColor, 1.0);

        #if defined RSM_ENABLED && defined RENDER_DEFERRED
            #if RSM_SCALE == 0 || defined RSM_UPSCALE
                //ivec2 iuv = ivec2(texcoord * viewSize);
                vec3 rsmColor = texelFetch(BUFFER_RSM_COLOR, gl_FragCoord.xy, 0).rgb;
            #else
                const float rsm_scale = 1.0 / exp2(RSM_SCALE);
                vec3 rsmColor = textureLod(BUFFER_RSM_COLOR, texcoord * rsm_scale, 0).rgb;
            #endif
        #endif

        #if DIRECTIONAL_LIGHTMAP_STRENGTH > 0
            vec3 blockLightAmbient = pow2(blockLight)*blockLightColor;
        #else
            vec3 blockLightAmbient = pow5(blockLight)*blockLightColor;
        #endif

        #if MATERIAL_FORMAT == MATERIAL_FORMAT_LABPBR || MATERIAL_FORMAT == MATERIAL_FORMAT_DEFAULT
            vec3 specularTint = GetHCM_Tint(material.albedo.rgb, material.hcm);
        #else
            vec3 specularTint = mix(vec3(1.0), material.albedo.rgb, material.f0);
        #endif

        vec3 ambient = vec3(MinWorldLux + blockLightAmbient);
        vec3 diffuse = vec3(0.0);
        vec3 specular = vec3(0.0);
        vec4 final = material.albedo;

        vec3 F = GetFresnel(material, NoVm, roughL);
        //return vec4(F * 500.0, 1.0);

        float Fmax = max(max(F.x, F.y), F.z);
        final.a += Fmax * max(1.0 - final.a, 0.0);

        //vec3 specFmax = vec3(0.0);
        #ifdef SHADOW_ENABLED
            //vec3 iblF = vec3(0.0);
            vec3 iblSpec = vec3(0.0);
            #if REFLECTION_MODE != REFLECTION_MODE_NONE
                vec2 envBRDF = textureLod(BUFFER_BRDF_LUT, vec2(NoVm, material.smoothness), 0).rg;
                envBRDF = RGBToLinear(vec3(envBRDF, 0.0)).rg;

                iblSpec = reflectColor * specularTint * (F * envBRDF.x + envBRDF.y) * material.occlusion;
            #endif

            float NoHm = max(dot(viewNormal, halfDir), 0.0);
            float VoHm = max(dot(viewDir, halfDir), 0.0);

            vec3 sunSpec = vec3(0.0);
            if (NoLm > EPSILON) {
                //vec3 sunF = GetFresnel(material, VoHm, roughL);
                sunSpec = GetSpecularBRDF(F, NoVm, NoLm, NoHm, roughL) * specularTint * skyLightColor * skyLight3 * shadowFinal;
                specular += sunSpec;

                final.a = min(final.a + luminance(sunSpec) * exposure, 1.0);
            }

            //specFmax = max(specFmax, sunF);

            float shadowBrightness = mix(0.5 * skyLight3, 0.95 * skyLight, rainStrength); // SHADOW_BRIGHTNESS
            vec3 skyAmbient = GetSkyAmbientLight(viewNormal) * shadowBrightness;
            ambient += skyAmbient;
            //return vec4(ambient, 1.0);

            float diffuseLightF = shadowFinal;

            #ifdef SSS_ENABLED
                //float ambientShadowBrightness = 1.0 - 0.5 * (1.0 - SHADOW_BRIGHTNESS);
                //vec3 ambient_sss = skyAmbient * material.scattering * material.occlusion;

                // Transmission
                //vec3 sss = shadowSSS * material.scattering * skyLightColor;// * max(-NoL, 0.0);
                diffuseLightF = mix(diffuseLightF, shadowSSS, material.scattering);
            #endif

            vec3 diffuseLight = diffuseLightF * skyLightColor * skyLight3;

            #if defined RSM_ENABLED && defined RENDER_DEFERRED
                diffuseLight += 20.0 * rsmColor * skyLightColor * material.scattering;
            #endif

            vec3 sunDiffuse = GetDiffuseBSDF(material, NoVm, NoLm, LoHm, roughL) * diffuseLight * material.albedo.a;
            diffuse += sunDiffuse;
        #endif

        //return vec4(iblSpec, 1.0);

        #ifdef RENDER_WATER
            vec3 upDir = normalize(upDirection);
            if (materialId == 1) {
                const float ScatteringCoeff = 0.11;

                //vec3 extinction = vec3(0.54, 0.91, 0.93);
                vec3 extinctionInv = 1.0 - WaterAbsorbtionExtinction;
                //vec3 extinction = 1.0 - material.albedo.rgb;

                #if WATER_REFRACTION != WATER_REFRACTION_NONE
                    float waterRefractEta = isEyeInWater == 1
                        ? IOR_WATER / IOR_AIR
                        : IOR_AIR / IOR_WATER;
                    
                    float refractDist = max(waterSolidDepth.y - waterSolidDepth.x, 0.0);

                    vec2 waterSolidDepthFinal;
                    vec3 refractColor = vec3(0.0);
                    vec3 refractDir = refract(vec3(0.0, 0.0, -1.0), viewNormal, waterRefractEta); // TODO: subtract geoViewNormal from texViewNormal
                    if (dot(refractDir, refractDir) > EPSILON) {
                        vec2 refractOffset = refractDir.xy;

                        // scale down contact point to avoid tearing
                        refractOffset *= min(0.1*refractDist, 0.06);

                        // scale down with distance
                        refractOffset *= pow2(1.0 - saturate((viewDist - near) / (far - near)));
                        
                        vec2 refractUV = screenUV + refractOffset;

                        // update water depth
                        waterSolidDepthFinal = GetWaterSolidDepth(refractUV);

                        #if WATER_REFRACTION == WATER_REFRACTION_FANCY
                            // TODO: dda trace screen-space path until rejected
                            // calculate dx , dy
                            //dx = X1 - X0;
                            //dy = Y1 - Y0;
                            vec2 startUV = refractUV;
                            vec2 d = screenUV - startUV;
                            vec2 dp = d * viewSize;

                            // Depending upon absolute value of dx & dy
                            // choose number of steps to put pixel as
                            // steps = abs(dx) > abs(dy) ? abs(dx) : abs(dy)
                            float stepCount = abs(dp.x) > abs(dp.y) ? abs(dp.x) : abs(dp.y);

                            if (stepCount > 1.0) {
                                // calculate increment in x & y for each steps
                                //Xinc = d.x / steps;
                                //Yinc = d.y / steps;
                                vec2 step = d / stepCount;

                                // Put pixel for each step

                                //refractUV = screenUV;
                                float solidViewDepth = 0.0;
                                for (int i = 0; i <= stepCount && solidViewDepth < viewDist; i++) {
                                    refractUV = startUV + i * step;
                                    solidViewDepth = textureLod(depthtex1, refractUV, 0).r;
                                    solidViewDepth = linearizeDepthFast(solidViewDepth, near, far);
                                }

                                waterSolidDepthFinal.y = solidViewDepth;//linearizeDepthFast(solidViewDepth, near, far);
                            }
                        #else
                            if (waterSolidDepthFinal.y < waterSolidDepthFinal.x) {
                                // refracted vector returned an invalid hit
                                waterSolidDepthFinal = waterSolidDepth;
                                refractUV = screenUV;

                            }
                        #endif

                        refractColor = textureLod(BUFFER_REFRACT, refractUV, 0).rgb / exposure;
                    }
                    else {
                        // TIR
                        waterSolidDepthFinal.x = 65000;
                        waterSolidDepthFinal.y = 65000;
                    }

                    float waterDepthFinal = isEyeInWater == 1 ? waterSolidDepthFinal.x
                        : max(waterSolidDepthFinal.y - waterSolidDepthFinal.x, 0.0);

                    vec3 scatterColor = material.albedo.rgb * skyLightColor * skyLight3;// * shadowFinal;

                    float verticalDepth = waterDepthFinal * max(dot(viewLightDir, upDir), 0.0);
                    vec3 absorption = exp(extinctionInv * -(verticalDepth + waterDepthFinal));
                    float inverseScatterAmount = 1.0 - exp(0.11 * -waterDepthFinal);

                    diffuse = (refractColor + scatterColor * inverseScatterAmount) * absorption;
                    final.a = 1.0;
                #else
                    //float waterSurfaceDepth = textureLod(shadowtex0);
                    //float solidSurfaceDepth = textureLod(shadowtex1);

                    float waterDepth = isEyeInWater == 1 ? waterSolidDepth.x
                        : max(waterSolidDepth.y - waterSolidDepth.x, 0.0);

                    vec3 scatterColor = material.albedo.rgb * skyLightColor * skyLight3;// * shadowFinal;

                    float verticalDepth = waterDepth * max(dot(viewLightDir, upDir), 0.0);
                    vec3 absorption = exp(extinctionInv * -(waterDepth + verticalDepth));
                    float scatterAmount = exp(0.1 * -waterDepth);

                    //diffuse = (diffuse + scatterColor * scatterAmount);// * absorption;
                    diffuse = scatterColor * scatterAmount + absorption;
                    
                    float alphaF = 1.0 - exp(2.0 * -waterDepth);
                    final.a += alphaF * max(1.0 - final.a, 0.0);
                    //final.a = 1.0;
                #endif
            }
        #endif

        #ifdef HANDLIGHT_ENABLED
            if (heldBlockLightValue > EPSILON)
                ApplyHandLighting(diffuse, specular, material, viewNormal, viewPos.xyz, viewDir, NoVm, roughL);
        #endif

        #if defined RSM_ENABLED && defined RENDER_DEFERRED
            ambient += rsmColor * skyLightColor;
        #endif

        #if MATERIAL_FORMAT == MATERIAL_FORMAT_LABPBR || MATERIAL_FORMAT == MATERIAL_FORMAT_DEFAULT
            if (material.hcm >= 0) {
                //if (material.hcm < 8) specular *= material.albedo.rgb;

                diffuse *= HCM_AMBIENT;
                ambient *= HCM_AMBIENT;
            }
        #else
            float metalDarkF = 1.0 - material.f0 * (1.0 - HCM_AMBIENT);
            diffuse *= metalDarkF;
            ambient *= metalDarkF;
        #endif

        //ambient += minLight;

        float emissive = material.emission*material.emission * EmissionLumens;

        // #ifdef RENDER_WATER
        //     //ambient = vec3(0.0);
        //     diffuse = vec3(0.0);
        //     specular = vec3(0.0);
        // #endif

        final.rgb = final.rgb * (ambient * material.occlusion + emissive) + diffuse * material.albedo.a * max(1.0 - F, 0.0) + specular + iblSpec;

        // #ifdef SSS_ENABLED
        //     //float ambientShadowBrightness = 1.0 - 0.5 * (1.0 - SHADOW_BRIGHTNESS);
        //     vec3 ambient_sss = skyAmbient * material.scattering * material.occlusion;

        //     // Transmission
        //     vec3 sss = (1.0 - shadowFinal) * shadowSSS * material.scattering * skyLightColor;// * max(-NoL, 0.0);
        //     final.rgb += material.albedo.rgb * invPI * (ambient_sss + sss);
        // #endif

        #ifdef RENDER_DEFERRED
            if (isEyeInWater == 1) {
                // apply scattering and absorption

                //float viewDepthLinear = linearizeDepthFast(gl_FragCoord.z, near, far);
                float viewDepth = textureLod(depthtex1, screenUV, 0).r;
                float viewDepthLinear = linearizeDepthFast(viewDepth, near, far);

                //float waterDepthFinal = isEyeInWater == 1 ? waterSolidDepthFinal.x
                //    : max(waterSolidDepthFinal.y - waterSolidDepthFinal.x, 0.0);

                //vec3 scatterColor = material.albedo.rgb * skyLightColor;// * shadowFinal;
                //float skyLight5 = pow5(skyLight);
                vec3 scatterColor = vec3(0.0178, 0.0566, 0.0754) * skyLight;// * shadowFinal;
                vec3 extinctionInv = 1.0 - WaterAbsorbtionExtinction;

                //float verticalDepth = waterDepthFinal * max(dot(viewLightDir, upDir), 0.0);
                //vec3 absorption = exp(extinctionInv * -(verticalDepth + waterDepthFinal));
                vec3 absorption = exp(extinctionInv * -viewDepthLinear);
                float inverseScatterAmount = 1.0 - exp(0.11 * -viewDepthLinear);

                final.rgb = (final.rgb + scatterColor * inverseScatterAmount) * absorption;

                //float vanillaWaterFogF = GetFogFactor(viewDist, near, waterFogEnd, 1.0);
                //final.rgb = mix(final.rgb, RGBToLinear(fogColor), vanillaWaterFogF);
            }
        #endif

        if (isEyeInWater == 1) {
            // TODO: Get this outa here (vertex shader)
            vec2 skyLightLevels = GetSkyLightLevels();
            float sunSkyLumen = GetSunLightLevel(skyLightLevels.x) * mix(DaySkyLumen, DaySkyOvercastLumen, rainStrength);
            float moonSkyLumen = GetMoonLightLevel(skyLightLevels.y) * NightSkyLumen;
            float skyLumen = sunSkyLumen + moonSkyLumen;

            // apply water fog
            float waterFogEnd = min(40.0, fogEnd);
            float waterFogF = GetFogFactor(viewDist, near, waterFogEnd, 0.5);
            vec3 waterFogColor = vec3(0.0178, 0.0566, 0.0754) * skyLumen;
            final.rgb = mix(final.rgb, waterFogColor, waterFogF);
        }
        else {
            #ifdef RENDER_DEFERRED
                ApplyFog(final.rgb, viewPos.xyz, skyLight);
            #elif defined RENDER_GBUFFER
                #if defined RENDER_WATER || defined RENDER_HAND_WATER
                    ApplyFog(final, viewPos.xyz, skyLight, EPSILON);
                #else
                    ApplyFog(final, viewPos.xyz, skyLight, alphaTestRef);
                #endif
            #endif
        }

        #ifdef VL_ENABLED
            mat4 matViewToShadowView = shadowModelView * gbufferModelViewInverse;

            vec4 shadowViewStart = matViewToShadowView * vec4(vec3(0.0), 1.0);
            shadowViewStart.xyz /= shadowViewStart.w;

            vec4 shadowViewEnd = matViewToShadowView * vec4(viewPos, 1.0);
            shadowViewEnd.xyz /= shadowViewEnd.w;

            float shadowBias = 0.0; // TODO: fuck

            float G_scattering = mix(G_SCATTERING_CLEAR, G_SCATTERING_RAIN, rainStrength);
            float volScatter = GetVolumetricLighting(shadowViewStart.xyz, shadowViewEnd.xyz, shadowBias, G_scattering);
            vec3 volLight = volScatter * (sunColor + moonColor);

            //final.a = min(final.a + luminance(volLight) * exposure, 1.0);
            final.rgb += volLight;
        #endif

        return final;
    }
#endif
