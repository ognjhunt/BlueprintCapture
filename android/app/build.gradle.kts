plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.hilt.android)
    alias(libs.plugins.google.services)
    alias(libs.plugins.ksp)
}

val mwdatAppId = providers.gradleProperty("MWDAT_APPLICATION_ID").orNull ?: ""
val mwdatClientToken = providers.gradleProperty("MWDAT_CLIENT_TOKEN").orNull ?: ""
val useMwdatDevAppId = providers.gradleProperty("MWDAT_USE_DEV_APP_ID").orNull?.toBoolean() ?: true
val useMwdatPrivateSdk = providers.gradleProperty("MWDAT_ENABLE_PRIVATE_SDK").orNull?.toBoolean() == true

android {
    namespace = "app.blueprint.capture"
    compileSdk = 36

    defaultConfig {
        applicationId = "Public.BlueprintCapture.Android"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }

        val backendBaseUrl = providers.gradleProperty("BLUEPRINT_BACKEND_BASE_URL").orNull ?: ""
        val demandBackendBaseUrl = providers.gradleProperty("BLUEPRINT_DEMAND_BACKEND_BASE_URL").orNull ?: ""
        val allowMockJobsFallback = providers.gradleProperty("BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK").orNull ?: "false"
        val enableOpenCaptureHere = providers.gradleProperty("BLUEPRINT_ENABLE_OPEN_CAPTURE_HERE").orNull ?: "true"
        val stripePublishableKey = providers.gradleProperty("BLUEPRINT_STRIPE_PUBLISHABLE_KEY").orNull ?: ""
        val nearbyDiscoveryProvider = providers.gradleProperty("BLUEPRINT_NEARBY_DISCOVERY_PROVIDER").orNull ?: "places_nearby"
        val enableGeminiMapsGroundingFallback =
            providers.gradleProperty("BLUEPRINT_ENABLE_GEMINI_MAPS_GROUNDING_FALLBACK").orNull ?: "false"

        buildConfigField("String", "BACKEND_BASE_URL", "\"$backendBaseUrl\"")
        buildConfigField("String", "DEMAND_BACKEND_BASE_URL", "\"$demandBackendBaseUrl\"")
        buildConfigField("boolean", "ALLOW_MOCK_JOBS_FALLBACK", allowMockJobsFallback)
        buildConfigField("boolean", "ENABLE_OPEN_CAPTURE_HERE", enableOpenCaptureHere)
        buildConfigField("String", "STRIPE_PUBLISHABLE_KEY", "\"$stripePublishableKey\"")
        buildConfigField("String", "NEARBY_DISCOVERY_PROVIDER", "\"$nearbyDiscoveryProvider\"")
        buildConfigField("boolean", "ENABLE_GEMINI_MAPS_GROUNDING_FALLBACK", enableGeminiMapsGroundingFallback)
        buildConfigField("boolean", "MWDAT_PRIVATE_SDK_ENABLED", useMwdatPrivateSdk.toString())
        manifestPlaceholders["blueprintAppScheme"] = "blueprint"
        manifestPlaceholders["mwdatApplicationId"] = mwdatAppId
        manifestPlaceholders["mwdatClientToken"] = mwdatClientToken
        buildConfigField("boolean", "MWDAT_USE_DEV_APP_ID", useMwdatDevAppId.toString())
    }

    buildTypes {
        debug {
            versionNameSuffix = "-debug"
            manifestPlaceholders["mwdatApplicationId"] = if (useMwdatDevAppId) "0" else mwdatAppId
            manifestPlaceholders["mwdatClientToken"] = if (useMwdatDevAppId) "" else mwdatClientToken
        }
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }

    sourceSets.named("main") {
        if (!useMwdatPrivateSdk) {
            java.srcDir("src/metaStub/kotlin")
        }
    }
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(platform(libs.androidx.compose.bom))
    implementation(platform(libs.firebase.bom))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.google.material)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.ui)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.coroutines.play.services)
    implementation(libs.kotlinx.serialization.json)

    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.hilt.navigation.compose)
    implementation(libs.androidx.hilt.work)
    ksp(libs.androidx.hilt.compiler)
    implementation(libs.androidx.work.runtime.ktx)

    implementation(libs.retrofit)
    implementation(libs.retrofit.moshi)
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)
    implementation(libs.moshi.kotlin)
    ksp(libs.moshi.kotlin.codegen)

    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.video)
    implementation(libs.androidx.camera.view)
    implementation(libs.google.ar.core)
    implementation(libs.androidx.xr.runtime)
    implementation(libs.androidx.xr.projected)
    implementation(libs.androidx.xr.glimmer)
    implementation(libs.androidx.xr.arcore)

    implementation(libs.firebase.auth)
    implementation(libs.firebase.analytics)
    implementation(libs.firebase.firestore)
    implementation(libs.firebase.storage)
    implementation(libs.firebase.messaging)
    implementation(libs.play.services.auth)
    implementation(libs.play.services.location)
    implementation(libs.androidx.credentials)
    implementation(libs.androidx.credentials.play.services)
    implementation(libs.maps.compose)
    implementation(libs.coil.compose)
    if (useMwdatPrivateSdk) {
        implementation(libs.mwdat.core)
        implementation(libs.mwdat.camera)
    }

    testImplementation(libs.junit4)
    testImplementation(libs.truth)

    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.espresso.core)
    androidTestImplementation(libs.androidx.ui.test.junit4)
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)
}
