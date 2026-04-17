import java.util.Properties
import java.io.FileInputStream
import java.util.zip.ZipFile
import java.util.zip.ZipEntry

// Load local.properties at the top-level so it's available everywhere
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.llmhub.llmhub"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.llmhub.llmhub"
        minSdk = 27
        targetSdk = 36
        versionCode = 93
        versionName = "3.7.1"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        val hfToken: String = localProperties.getProperty("HF_TOKEN", "")
        buildConfigField("String", "HF_TOKEN", "\"$hfToken\"")
        val debugPremium: Boolean = localProperties.getProperty("DEBUG_PREMIUM", "false").toBoolean()
        buildConfigField("Boolean", "DEBUG_PREMIUM", "$debugPremium")

        // AdMob IDs — override in local.properties; test IDs are the defaults
        val admobAppId: String = localProperties.getProperty(
            "ADMOB_APP_ID", "ca-app-pub-3940256099942544~3347511713")
        val admobBannerId: String = localProperties.getProperty(
            "ADMOB_BANNER_ID", "ca-app-pub-3940256099942544/6300978111")
        val admobInterstitialId: String = localProperties.getProperty(
            "ADMOB_INTERSTITIAL_ID", "ca-app-pub-3940256099942544/1033173712")
        val admobRewardedId: String = localProperties.getProperty(
            "ADMOB_REWARDED_ID", "ca-app-pub-3940256099942544/5224354917")
        buildConfigField("String", "ADMOB_APP_ID", "\"$admobAppId\"")
        buildConfigField("String", "ADMOB_BANNER_ID", "\"$admobBannerId\"")
        buildConfigField("String", "ADMOB_INTERSTITIAL_ID", "\"$admobInterstitialId\"")
        buildConfigField("String", "ADMOB_REWARDED_ID", "\"$admobRewardedId\"")
        manifestPlaceholders["admobAppId"] = admobAppId
        
        // Enable 16KB page size support for Android 15+ compatibility
        ndk {
            abiFilters += setOf("arm64-v8a")
            debugSymbolLevel = "FULL"
        }
    }
    
    androidResources {
        localeFilters += listOf("en", "es", "pt", "de", "fr", "ru", "it", "tr", "pl", "ar", "ja", "id", "in", "ko", "fa", "he", "iw", "uk", "zh")
    }

    assetPacks += mutableSetOf(":qnn_pack", ":sd_pack", ":nexa_npu_pack")

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            ndk {
                debugSymbolLevel = "NONE"
            }
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
        }
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.0"
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "META-INF/LICENSE-LGPL-3.txt"
            excludes += "META-INF/LICENSE-LGPL-3.0.txt"
            excludes += "META-INF/LICENSE*"
            excludes += "META-INF/DEPENDENCIES"
            excludes += "META-INF/DEPENDENCIES.txt"
            excludes += "META-INF/NOTICE"
            excludes += "META-INF/NOTICE.txt"
            excludes += "META-INF/LICENSE.txt"
            excludes += "META-INF/*.kotlin_module"
            excludes += "google/protobuf/*.proto"
        }
        jniLibs {
            useLegacyPackaging = true
            pickFirsts += setOf("**/libmediapipe_tasks_text_jni.so")
            pickFirsts += setOf("**/libonnxruntime.so")
            excludes += setOf("**/libdeepseek-ocr.so")
            excludes += setOf("**/libstable-diffusion.so")
        }
    }
    
    bundle {
        language {
            enableSplit = false
        }
    }
}

configurations.all {
    resolutionStrategy {
        force("com.google.protobuf:protobuf-java:3.25.1")
        force("com.microsoft.onnxruntime:onnxruntime-android:1.24.1")
    }
    exclude(group = "com.google.protobuf", module = "protobuf-javalite")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)
    implementation(libs.retrofit)
    implementation(libs.retrofit.gson)
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)
    implementation(libs.kotlinx.coroutines.android)
    implementation("androidx.localbroadcastmanager:localbroadcastmanager:1.1.0")
    implementation("androidx.datastore:datastore-preferences:1.0.0")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation(libs.accompanist.permissions)
    implementation(libs.coil.compose)
    implementation(libs.gson)
    implementation("org.apache.commons:commons-csv:1.10.0")
    implementation("com.itextpdf:itext7-core:7.2.5")
    implementation("io.ktor:ktor-client-android:2.3.6")
    implementation("io.ktor:ktor-client-content-negotiation:2.3.6")
    implementation("io.ktor:ktor-serialization-kotlinx-json:2.3.6")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.mediapipe:tasks-genai:0.10.33")
    implementation("com.google.mediapipe:tasks-vision:0.10.33")
    implementation("com.google.mediapipe:tasks-text:0.10.33")
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.10.0")
    implementation("com.google.protobuf:protobuf-java:3.25.1")
    implementation("org.slf4j:slf4j-nop:2.0.9")
    implementation("com.google.ai.edge.localagents:localagents-rag:0.3.0")
    implementation("com.github.jeziellago:compose-markdown:0.3.0")
    implementation("com.vladsch.flexmark:flexmark-all:0.64.8")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.24.1")

    implementation("ai.nexa:core:0.0.24") {
        exclude(group = "com.microsoft.onnxruntime")
    }

    implementation("com.google.android.play:asset-delivery:2.2.2")
    implementation("com.google.android.play:asset-delivery-ktx:2.2.2")
    implementation("com.android.billingclient:billing-ktx:7.1.1")
    implementation("com.google.android.gms:play-services-ads:23.6.0")
    implementation("com.google.android.ump:user-messaging-platform:3.1.0")

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test.junit4)
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)
}

val nexaAarConfig by configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
}
dependencies { nexaAarConfig("ai.nexa:core:0.0.24@aar") }

val npuPackAssetsDir = rootProject.file("nexa_npu_pack/src/main/assets/npu")

val extractNexaNpuAssets by tasks.registering {
    description = "Extracts npu/htp-files-v81/ and htp-files-v85/ from Nexa AAR into nexa_npu_pack"
    group = "build setup"
    inputs.files(nexaAarConfig)
    outputs.dir(npuPackAssetsDir)
    outputs.upToDateWhen {
        npuPackAssetsDir.resolve("htp-files-v81").exists() &&
        npuPackAssetsDir.resolve("htp-files-v85").exists()
    }
    doLast {
        val aar = nexaAarConfig.singleFile
        npuPackAssetsDir.deleteRecursively()
        npuPackAssetsDir.mkdirs()
        var extracted = 0
        ZipFile(aar).use { zip ->
            zip.entries().toList().asSequence()
                .filter { !it.isDirectory && it.name.startsWith("assets/npu/htp-files-v") }
                .forEach { entry ->
                    val rel = entry.name.removePrefix("assets/npu/")
                    val target = npuPackAssetsDir.resolve(rel)
                    target.parentFile.mkdirs()
                    zip.getInputStream(entry).use { src ->
                        target.outputStream().use { dst -> src.copyTo(dst) }
                    }
                    extracted++
                }
        }
        logger.lifecycle("extractNexaNpu: extracted $extracted files → ${npuPackAssetsDir.absolutePath}")
    }
}

val isBundleBuild = gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) }

if (isBundleBuild) {
    tasks.configureEach {
        val n = name
        if ((n.startsWith("merge") && n.contains("Assets", ignoreCase = true)) ||
            (n.startsWith("assetPack") && n.contains("PreBundleTask", ignoreCase = true))
        ) {
            dependsOn(extractNexaNpuAssets)
        }
    }
}

if (isBundleBuild) {
    tasks.configureEach {
        if (name.startsWith("merge") && name.contains("Assets", ignoreCase = true)) {
            outputs.upToDateWhen { false }
            doLast {
                outputs.files.forEach { outDir ->
                    outDir.resolve("cvtbase").deleteRecursively()
                    outDir.resolve("qnnlibs").deleteRecursively()
                }
                outputs.files.asFileTree.matching { include("npu/**") }
                    .filter { it.isFile }
                    .forEach { f ->
                        logger.lifecycle("stripBundleAssets: removed ${f.parentFile.name}/${f.name} from base module")
                        f.delete()
                    }
                outputs.files.asFileTree.matching { include("npu/**") }
                    .filter { it.isDirectory }
                    .sortedByDescending { it.absolutePath.length }
                    .forEach { it.delete() }
                outputs.files.asFileTree.matching { include("npu") }
                    .filter { it.isDirectory && (it.listFiles()?.isEmpty() == true) }
                    .forEach { it.delete() }
            }
        }
    }
}

val qnnlibsDir = project.file("src/main/assets/qnnlibs")
val qnnlibsHiddenDir = project.file("src/main/assets/.qnnlibs_hidden")
val cvtbaseDir = project.file("src/main/assets/cvtbase")
val cvtbaseHiddenDir = project.file("src/main/assets/.cvtbase_hidden")

tasks.register("hideAssetsForBundle") {
    doLast {
        if (qnnlibsDir.exists() && !qnnlibsHiddenDir.exists()) {
            logger.lifecycle("Hiding qnnlibs from base module for AAB build (will use asset pack)")
            qnnlibsDir.renameTo(qnnlibsHiddenDir)
        }
        if (cvtbaseDir.exists() && !cvtbaseHiddenDir.exists()) {
            logger.lifecycle("Hiding cvtbase from base module for AAB build (will use sd_pack)")
            cvtbaseDir.renameTo(cvtbaseHiddenDir)
        }
    }
}

tasks.register("restoreAssetsAfterBundle") {
    doLast {
        if (qnnlibsHiddenDir.exists()) {
            logger.lifecycle("Restoring qnnlibs to app/src/main/assets")
            qnnlibsHiddenDir.renameTo(qnnlibsDir)
        }
        if (cvtbaseHiddenDir.exists()) {
            logger.lifecycle("Restoring cvtbase to app/src/main/assets")
            cvtbaseHiddenDir.renameTo(cvtbaseDir)
        }
    }
}

tasks.register("ensureAssetsForApk") {
    doLast {
        if (qnnlibsHiddenDir.exists() && !qnnlibsDir.exists()) {
            logger.lifecycle("Restoring qnnlibs for APK build")
            qnnlibsHiddenDir.renameTo(qnnlibsDir)
        }
        if (cvtbaseHiddenDir.exists() && !cvtbaseDir.exists()) {
            logger.lifecycle("Restoring cvtbase for APK build")
            cvtbaseHiddenDir.renameTo(cvtbaseDir)
        }
    }
}

tasks.configureEach {
    if (name.startsWith("bundle") && name.contains("Release", ignoreCase = true)) {
        finalizedBy("restoreAssetsAfterBundle")
    }
    if (name.startsWith("assemble") && name.contains("Release", ignoreCase = true)) {
        dependsOn("ensureAssetsForApk")
    }
}
