plugins {
    id("com.android.ai-pack")
}

aiPack {
    packName.set("ai_models")
    dynamicDelivery {
        deliveryType.set("install-time")
    }
}
