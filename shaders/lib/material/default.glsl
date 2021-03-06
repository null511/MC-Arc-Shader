void ApplyHardCodedMaterials() {
    matSmooth = 0.08;
    matSSS = 0.0;
    matF0 = 0.04;

    if (mc_Entity.x == 100.0) {
        // Water
        matSmooth = 0.96;
        matF0 = 0.02;
    }
    else if (mc_Entity.x >= 10001.0 && mc_Entity.x <= 10004.0) {
        // Foliage
        matSmooth = 0.16;
        matSSS = 0.85;
        matF0 = 0.03;
    }
    else if (mc_Entity.x >= 11000.0 && mc_Entity.x < 11010) {
        // Metals
        if (mc_Entity.x == 11000) {
            // Iron
            matSmooth = 0.8;
            matF0 = 230.5/255.0;
        }
        else if (mc_Entity.x == 11001) {
            // Gold
            matSmooth = 0.9;
            matF0 = 231.5/255.0;
        }
        else if (mc_Entity.x == 11004) {
            // Copper
            matSmooth = 0.75;
            matF0 = 234.5/255.0;
        }
    }
    else if (mc_Entity.x >= 11010.0 && mc_Entity.x < 11100) {
        // SSS
        if (mc_Entity.x == 11010) {
            // Snow
            matSmooth = 0.4;
            matF0 = 0.02;
            matSSS = 0.5;
        }
        else if (mc_Entity.x == 11011) {
            // Slime
            matSmooth = 0.55;
            matF0 = 0.04;
            matSSS = 0.6;
        }
    }
    else if (mc_Entity.x >= 11100.0 && mc_Entity.x < 11200) {
        // Smooth
        if (mc_Entity.x == 11100) {
            // Ice
            matSmooth = 0.94;
            matF0 = 0.02;
            matSSS = 0.9;
        }
        else if (mc_Entity.x == 11101) {
            // Polished blocks
            matSmooth = 0.65;
            matF0 = 0.04;
        }
    }
    else if (mc_Entity.x >= 11200.0) {
        // Special
        if (mc_Entity.x == 11200) {
            // Diamond
            matSmooth = 0.98;
            matF0 = 0.172;
            matSSS = 0.9;
        }
        else if (mc_Entity.x == 11201) {
            // Emerald
            matSmooth = 0.8;
            matF0 = 0.053;
            matSSS = 0.6;
        }
        else if (mc_Entity.x == 11202) {
            // Obsidian
            matSmooth = 0.94;
            matF0 = 0.047;
            matSSS = 0.2;
        }
    }
}
