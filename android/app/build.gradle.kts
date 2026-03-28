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
        val mainWebsiteUrl = providers.gradleProperty("BLUEPRINT_MAIN_WEBSITE_URL").orNull ?: "https://www.tryblueprint.io"
        val helpCenterUrl =
            providers.gradleProperty("BLUEPRINT_HELP_CENTER_URL").orNull
                ?: "mailto:support@blueprint.app?subject=Blueprint%20Help"
        val bugReportUrl =
            providers.gradleProperty("BLUEPRINT_BUG_REPORT_URL").orNull
                ?: "mailto:bugs@blueprint.app?subject=Blueprint%20Bug%20Report"
        val termsOfServiceUrl =
            providers.gradleProperty("BLUEPRINT_TERMS_OF_SERVICE_URL").orNull ?: "https://www.tryblueprint.io/terms"
        val privacyPolicyUrl =
            providers.gradleProperty("BLUEPRINT_PRIVACY_POLICY_URL").orNull ?: "https://www.tryblueprint.io/privacy"
        val capturePolicyUrl =
            providers.gradleProperty("BLUEPRINT_CAPTURE_POLICY_URL").orNull ?: "https://www.tryblueprint.io/capture-policy"
        val accountDeletionUrl =
            providers.gradleProperty("BLUEPRINT_ACCOUNT_DELETION_URL").orNull ?: "https://www.tryblueprint.io/account/delete"
        val supportEmailAddress =
            providers.gradleProperty("BLUEPRINT_SUPPORT_EMAIL_ADDRESS").orNull ?: "support@blueprint.app"

        buildConfigField("String", "BACKEND_BASE_URL", "\"$backendBaseUrl\"")
        buildConfigField("String", "DEMAND_BACKEND_BASE_URL", "\"$demandBackendBaseUrl\"")
        buildConfigField("boolean", "ALLOW_MOCK_JOBS_FALLBACK", allowMockJobsFallback)
        buildConfigField("boolean", "ENABLE_OPEN_CAPTURE_HERE", enableOpenCaptureHere)
        buildConfigField("String", "STRIPE_PUBLISHABLE_KEY", "\"$stripePublishableKey\"")
        buildConfigField("String", "NEARBY_DISCOVERY_PROVIDER", "\"$nearbyDiscoveryProvider\"")
        buildConfigField("boolean", "ENABLE_GEMINI_MAPS_GROUNDING_FALLBACK", enableGeminiMapsGroundingFallback)
        buildConfigField("String", "MAIN_WEBSITE_URL", "\"$mainWebsiteUrl\"")
        buildConfigField("String", "HELP_CENTER_URL", "\"$helpCenterUrl\"")
        buildConfigField("String", "BUG_REPORT_URL", "\"$bugReportUrl\"")
        buildConfigField("String", "TERMS_OF_SERVICE_URL", "\"$termsOfServiceUrl\"")
        buildConfigField("String", "PRIVACY_POLICY_URL", "\"$privacyPolicyUrl\"")
        buildConfigField("String", "CAPTURE_POLICY_URL", "\"$capturePolicyUrl\"")
        buildConfigField("String", "ACCOUNT_DELETION_URL", "\"$accountDeletionUrl\"")
        buildConfigField("String", "SUPPORT_EMAIL_ADDRESS", "\"$supportEmailAddress\"")
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

tasks.register("validateExternalAlphaReleaseConfig") {
    group = "verification"
    description = "Validates Android release-safe config for the external alpha rollout."

    doLast {
        fun gradleProperty(name: String): String =
            (project.findProperty(name) as String?)?.trim().orEmpty()

        fun requireNonBlank(name: String, message: String) {
            if (gradleProperty(name).isBlank()) {
                throw org.gradle.api.GradleException(message)
            }
        }

        requireNonBlank(
            "BLUEPRINT_BACKEND_BASE_URL",
            "BLUEPRINT_BACKEND_BASE_URL must be set for Android external alpha builds.",
        )
        requireNonBlank(
            "BLUEPRINT_DEMAND_BACKEND_BASE_URL",
            "BLUEPRINT_DEMAND_BACKEND_BASE_URL must be set for Android external alpha builds.",
        )

        if (gradleProperty("BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK").ifBlank { "false" }.toBoolean()) {
            throw org.gradle.api.GradleException(
                "BLUEPRINT_ALLOW_MOCK_JOBS_FALLBACK must be false for Android external alpha builds.",
            )
        }

        if (gradleProperty("BLUEPRINT_ENABLE_GEMINI_MAPS_GROUNDING_FALLBACK").ifBlank { "false" }.toBoolean()) {
            throw org.gradle.api.GradleException(
                "BLUEPRINT_ENABLE_GEMINI_MAPS_GROUNDING_FALLBACK must stay false for Android external alpha builds.",
            )
        }

        val nearbyProvider = gradleProperty("BLUEPRINT_NEARBY_DISCOVERY_PROVIDER").ifBlank { "places_nearby" }
        if (nearbyProvider != "places_nearby") {
            throw org.gradle.api.GradleException(
                "BLUEPRINT_NEARBY_DISCOVERY_PROVIDER must be places_nearby for Android external alpha builds.",
            )
        }

        listOf(
            "BLUEPRINT_MAIN_WEBSITE_URL" to "website",
            "BLUEPRINT_HELP_CENTER_URL" to "help center",
            "BLUEPRINT_BUG_REPORT_URL" to "bug report",
            "BLUEPRINT_TERMS_OF_SERVICE_URL" to "terms of service",
            "BLUEPRINT_PRIVACY_POLICY_URL" to "privacy policy",
            "BLUEPRINT_CAPTURE_POLICY_URL" to "capture policy",
            "BLUEPRINT_ACCOUNT_DELETION_URL" to "account deletion",
            "BLUEPRINT_SUPPORT_EMAIL_ADDRESS" to "support email",
        ).forEach { (propertyName, label) ->
            requireNonBlank(
                propertyName,
                "Set $propertyName for the Android external alpha build so the $label surface is not a dead end.",
            )
        }

        if (!file("google-services.json").exists()) {
            throw org.gradle.api.GradleException(
                "android/app/google-services.json is required for Android external alpha builds.",
            )
        }

        val manifestText = file("src/main/AndroidManifest.xml").readText()
        if (!manifestText.contains("android.permission.POST_NOTIFICATIONS")) {
            throw org.gradle.api.GradleException(
                "AndroidManifest.xml must keep POST_NOTIFICATIONS declared for release validation.",
            )
        }

        println("Android external alpha release config looks valid.")
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
    implementation(libs.firebase.ai)
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
