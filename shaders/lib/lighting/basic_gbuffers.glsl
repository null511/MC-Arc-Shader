#ifdef RENDER_VERTEX
    <empty>
#endif

#ifdef RENDER_FRAG
    void BasicLighting(const in mat2 dFdXY, out vec4 colorMap, out float shadow) {
        colorMap = texture2DGrad(gtexture, texcoord, dFdXY[0], dFdXY[1]) * glcolor;
        if (colorMap.a < alphaTestRef) discard;

        const float minSkylightThreshold = 1.0 / 32.0 + EPSILON;
        shadow = step(minSkylightThreshold, lmcoord.y);

        #ifdef SHADOW_ENABLED
            shadow *= step(EPSILON, geoNoL);

            #if SHADOW_TYPE != 0
                if (shadow > 0.0) {
                    shadow *= GetShadowing(shadowPos);

                    // #if SHADOW_COLORS == 1
                    //     vec3 shadowColor = GetShadowColor();

                    //     shadowColor = mix(vec3(1.0), shadowColor, shadow);

                    //     //also make colors less intense when the block light level is high.
                    //     shadowColor = mix(shadowColor, vec3(1.0), blockLight);

                    //     lightColor *= shadowColor;
                    // #endif
                }
            #endif
        #endif
        
        colorMap.a = 1.0;
    }
#endif
