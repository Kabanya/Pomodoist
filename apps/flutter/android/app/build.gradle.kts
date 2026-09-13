import java.security.KeyStore
import java.security.cert.X509Certificate
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Secrets belong in the environment or ignored android/key.properties, never
// in dart-defines (which are compiled into the distributed application).
val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.isFile) {
    signingPropertiesFile.inputStream().use { signingProperties.load(it) }
}
fun signingValue(environment: String, property: String): String? =
    System.getenv(environment)?.takeIf { it.isNotBlank() }
        ?: signingProperties.getProperty(property)?.takeIf { it.isNotBlank() }

val releaseStorePath = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("ANDROID_STORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
val releaseStoreFile = releaseStorePath?.let { rootProject.file(it) }

fun validateReleaseSigning() {
    val storeFile = releaseStoreFile
    val storePassword = releaseStorePassword
    val keyAlias = releaseKeyAlias
    val keyPassword = releaseKeyPassword
    if (storeFile == null || !storeFile.isFile || storePassword == null ||
        keyAlias == null || keyPassword == null) {
        throw GradleException(
            "Android release signing is required. Configure ANDROID_KEYSTORE_PATH, " +
                "ANDROID_STORE_PASSWORD, ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD " +
                "or android/key.properties. See tool/android/README.md."
        )
    }
    if (keyAlias.equals("androiddebugkey", ignoreCase = true)) {
        throw GradleException("Android debug keys must not sign release builds.")
    }
    try {
        val store = KeyStore.getInstance(storeFile, storePassword.toCharArray())
        if (!store.isKeyEntry(keyAlias) ||
            store.getKey(keyAlias, keyPassword.toCharArray()) == null) {
            throw GradleException("The release alias must contain a private key.")
        }
        val certificate = store.getCertificate(keyAlias) as? X509Certificate
            ?: throw GradleException("The release alias must have an X.509 certificate.")
        certificate.checkValidity()
        if (certificate.subjectX500Principal.name.contains("CN=Android Debug", ignoreCase = true)) {
            throw GradleException("Android Debug certificates must not sign release builds.")
        }
    } catch (error: GradleException) {
        throw error
    } catch (_: Exception) {
        // Do not print passwords, keystore contents, or nested provider errors.
        throw GradleException("Cannot unlock the Android release key or its certificate is invalid.")
    }
}

// Guard the actual task graph, not only a guessed command name: Flutter,
// assemble, bundle, install and abbreviated Gradle release tasks are covered.
// Debug builds and IDE synchronization do not need signing credentials.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release", ignoreCase = true) }) {
        validateReleaseSigning()
    }
}

android {
    namespace = "com.finchforge.pomodoist"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
    defaultConfig {
        applicationId = "com.finchforge.pomodoist"
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
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
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
