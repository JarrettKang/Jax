import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Fixture builds must never share the real-data app's package/data directory.
val entryTarget = providers.gradleProperty("target").orNull.orEmpty().replace('\\', '/')
val worldFixture = entryTarget.endsWith("tool/world_attention_fixture.dart") ||
    entryTarget.endsWith("integration_test/world_attention_gesture_test.dart")
check(!worldFixture || gradle.startParameter.taskNames.none { it.contains("release", ignoreCase = true) }) {
    "World fixture entry points are Debug-only; never publish a fixture as Jax."
}

// Secrets are local only. Environment values take precedence per field.
val localSigning = Properties()
val localSigningFile = rootProject.file("key.properties")
if (localSigningFile.isFile) {
    localSigningFile.inputStream().use { localSigning.load(it) }
}
fun signingValue(environment: String, property: String): String? =
    providers.environmentVariable(environment).orNull?.takeIf { it.isNotBlank() }
        ?: localSigning.getProperty(property)?.takeIf { it.isNotBlank() }

val releaseStorePath = signingValue("JAX_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("JAX_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("JAX_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("JAX_KEY_PASSWORD", "keyPassword")
val releaseStoreFile = releaseStorePath?.let { rootProject.file(it) }

val validateJaxReleaseSigning = tasks.register("validateJaxReleaseSigning") {
    group = "verification"
    description = "Require private release signing credentials; never use the debug key."
    doLast {
        if (releaseStorePath == null || releaseStorePassword == null ||
            releaseKeyAlias == null || releaseKeyPassword == null) {
            throw GradleException(
                "Release signing credentials not configured. Set JAX_KEYSTORE_PATH, " +
                "JAX_KEYSTORE_PASSWORD, JAX_KEY_ALIAS and JAX_KEY_PASSWORD, or create " +
                "ignored android/key.properties from key.properties.example. " +
                "Debug builds do not require these credentials."
            )
        }
        if (releaseStoreFile?.isFile != true) {
            throw GradleException("Configured release keystore is missing or is not a file.")
        }
    }
}
// Covers assembleRelease/bundleRelease and aggregate tasks that include Release.
// The check also precedes AGP's signing validation, yielding a useful error.
tasks.configureEach {
    if (name == "preReleaseBuild" || name == "validateSigningRelease") {
        dependsOn(validateJaxReleaseSigning)
    }
}

android {
    namespace = "com.jarrett.jax"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.jarrett.jax"
        manifestPlaceholders["jaxAppLabel"] = "Jax"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFile
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        debug {
            if (worldFixture) {
                applicationIdSuffix = ".worldfixture"
                manifestPlaceholders["jaxAppLabel"] = "Jax World QA"
            }
        }
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
