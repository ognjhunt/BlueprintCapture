pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// Load local.properties so secrets stay out of version control.
val localProps = java.util.Properties().apply {
    val f = File(rootDir, "local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // Meta MWDAT SDK — credentials come from android/local.properties (gpr.user / gpr.token).
        maven {
            url = uri("https://maven.pkg.github.com/facebook/meta-wearables-dat-android")
            credentials {
                username = localProps.getProperty("gpr.user")
                    ?: providers.gradleProperty("gpr.user").orNull
                    ?: System.getenv("GITHUB_ACTOR") ?: ""
                password = localProps.getProperty("gpr.token")
                    ?: providers.gradleProperty("gpr.token").orNull
                    ?: System.getenv("GITHUB_TOKEN") ?: ""
            }
        }
    }
}

rootProject.name = "BlueprintCaptureAndroid"
include(":app")
