import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // Flutter Gradle 插件必须在 Android / Kotlin 插件之后应用。
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// 签名配置（android/key.properties，不提交到 git）
//   CI 里由 .github/workflows/release.yml 从 Secrets 生成该文件与 keystore。
//   这里刻意采用 Flutter 官方文档的标准写法，不改动 android{} 内 SDK 版本的
//   声明方式 —— 2026-09-11 排查 CI 时发现，任何额外的东西都可能让 AGP 9.1
//   在 afterEvaluate 阶段误判「project ':app' does not specify compileSdk」。
// ---------------------------------------------------------------------------
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val hasReleaseSigning = keystorePropertiesFile.exists()

android {
    namespace = "top.theez.pkwdwpl_lite"

    // 跟随 Flutter SDK 默认值（3.47 = 36，≥ 需求要求的 API 34；
    // 低于 34 会在 CI 的 "Check SDK API level" 步骤直接失败）。
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "top.theez.pkwdwpl_lite"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // key.properties 里的路径相对 android/ 目录（与 APRSLocus 一致）
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // 本地没配签名时用 debug key 先跑通；CI 发版会强制要求真签名。
                signingConfigs.getByName("debug")
            }
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
