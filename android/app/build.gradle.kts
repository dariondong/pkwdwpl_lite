// ---------------------------------------------------------------------------
// PKWDWPL Lite — Android 应用模块
//
// 签名策略（三种来源，按优先级）：
//   1. key.properties（推荐，与 APRSLocus 一致）
//        android/key.properties 内容形如：
//          storePassword=xxx
//          keyPassword=xxx
//          keyAlias=pkwdwpl
//          storeFile=keystore/release.keystore     ← 相对 android/ 目录
//        CI 里由 .github/workflows/release.yml 从 Secrets 生成这个文件。
//   2. 环境变量（备选）
//        SIGNING_KEY_PATH / STORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD
//   3. 都没有 → 回退 debug 签名，保证 `flutter build apk --release` 还能出包
//      （仅用于本地跑通流程；正式发版必须配好签名，CI 会强制检查）
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

/** 优先读环境变量（CI 备选路径），其次 android/key.properties。 */
fun signingValue(envName: String, propertyName: String): String? =
    System.getenv(envName) ?: keystoreProperties.getProperty(propertyName)

/**
 * 解析 keystore 路径。
 *
 * key.properties 里的路径是**相对 android/** 的（与 APRSLocus 的写法一致，
 * 例如 `storeFile=keystore/release.keystore`），所以这里必须用 rootProject.file()
 * 而不是模块内的 file()（后者会解析成 android/app/keystore/... 而找不到文件）。
 * 绝对路径则原样使用。
 */
fun resolveKeystoreFile(): File? {
    val path = signingValue("SIGNING_KEY_PATH", "storeFile") ?: "keystore/release.keystore"
    val candidate = File(path).let { if (it.isAbsolute) it else rootProject.file(path) }
    return if (candidate.exists()) candidate else null
}

/** 配置了签名配置（key.properties 存在，或有环境变量）且 keystore 文件确实存在。 */
val releaseKeystore: File? = resolveKeystoreFile()
val hasReleaseSigning: Boolean =
    releaseKeystore != null &&
        (keystorePropertiesFile.exists() || System.getenv("STORE_PASSWORD") != null)

android {
    namespace = "top.theez.pkwdwpl_lite"

    // 需求：compileSdk / targetSdk 至少 API 34。这里给到 36
    // （Flutter 3.47 模板 + 内置蓝牙插件均已按 36 编译）。
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "top.theez.pkwdwpl_lite"
        // 经典蓝牙 SPP 插件要求 21+；23 可省掉一批运行时权限的兼容分支。
        minSdk = 23
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = releaseKeystore
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
                // 本地没配签名时用 debug key 先跑通；CI 发版会强制要求真签名。
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
