// ---------------------------------------------------------------------------
// PKWDWPL Lite — Android 应用模块
//
// 签名策略（CI 与本地通用）：
//   1. CI：环境变量优先（由 GitHub Secrets 注入）
//        SIGNING_KEY        base64 后的 keystore（在 workflow 里解码成 android/app/release.jks）
//        KEY_ALIAS / KEY_PASSWORD / STORE_PASSWORD
//        SIGNING_KEY_PATH   可选，默认 release.jks（相对本模块目录）
//   2. 本地：android/key.properties（参考 android/key.properties.example，已被 .gitignore 忽略）
//   3. 都没有：自动回退用 debug 签名，保证 `flutter build apk --release` 仍能出包
// ---------------------------------------------------------------------------
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // Flutter Gradle 插件必须在 Android / Kotlin 插件之后应用。
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

/** 优先读环境变量（CI），其次 key.properties（本地）。 */
fun signingValue(envName: String, propertyName: String): String? =
    System.getenv(envName) ?: keystoreProperties.getProperty(propertyName)

/** 是否配置了 release 签名。 */
val hasReleaseSigning: Boolean =
    System.getenv("SIGNING_KEY") != null ||
        System.getenv("STORE_PASSWORD") != null ||
        keystorePropertiesFile.exists()

android {
    namespace = "top.theez.pkwdwpl_lite"

    // 需求 5：compileSdk / targetSdk 至少 API 34。
    // 这里给到 36（Flutter 3.47 + 蓝牙插件均已按 36 编译）。
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "top.theez.pkwdwpl_lite"
        // 经典蓝牙 SPP 插件要求 21+；23 能省掉一堆运行时权限的兼容分支。
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(signingValue("SIGNING_KEY_PATH", "storeFile") ?: "release.jks")
                storePassword = signingValue("STORE_PASSWORD", "storePassword")
                keyAlias = signingValue("KEY_ALIAS", "keyAlias")
                keyPassword = signingValue("KEY_PASSWORD", "keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // 没配置签名时用 debug key，让 CI/本地先跑通流程。
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }

    packaging {
        resources {
            excludes += setOf("META-INF/*.kotlin_module")
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
