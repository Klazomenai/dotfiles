---
name: android
description: >-
  Android/Kotlin development — Gradle Kotlin DSL, JNI/AAR native library
  integration (Sherpa-ONNX for ASR and TTS with piper ONNX models), Android
  Keystore credential storage, Bluetooth headset audio, and F-Droid reproducible
  build requirements. Use when writing Android/Kotlin code, reviewing Android PRs,
  or configuring Gradle/JNI tooling.
---

# Android Skill

## Project Structure

- Gradle Kotlin DSL (`build.gradle.kts`) as the single build config format — no Groovy `.gradle` files.
- Standard module layout: `app/src/main/` (production), `app/src/test/` (JVM unit tests), `app/src/androidTest/` (instrumented tests on device/emulator).
- Minimum SDK: **API 28** (Android 9) for StrongBox Keystore hardware backing. Sherpa-ONNX supports minSdk 21 — keep app minSdk at 28 for Keystore guarantees.
- `settings.gradle.kts` defines `dependencyResolutionManagement.repositories`; do not add repo declarations in module-level `build.gradle.kts`.
- `gradle/libs.versions.toml` (version catalog) for all dependency version pins — single source of truth, prevents drift.

## Native Library Integration (JNI/AAR) — Sherpa-ONNX

Sherpa-ONNX (`com.k2fsa.sherpa.onnx`) is the primary library for on-device ASR and TTS. It runs piper-format ONNX voice models natively on Android with an Apache 2.0 license.

**Sherpa-ONNX is not published to Maven Central or JitPack.** Build the AAR from GitHub releases:

```bash
# Download pre-compiled JNI libs for the target version
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.12.29/sherpa-onnx-v1.12.29-android.tar.bz2
tar xvf sherpa-onnx-v1.12.29-android.tar.bz2

# Copy .so files into the AAR source tree
cp jniLibs/arm64-v8a/*   android/SherpaOnnxAar/sherpa_onnx/src/main/jniLibs/arm64-v8a/
cp jniLibs/armeabi-v7a/* android/SherpaOnnxAar/sherpa_onnx/src/main/jniLibs/armeabi-v7a/
cp jniLibs/x86/*         android/SherpaOnnxAar/sherpa_onnx/src/main/jniLibs/x86/
cp jniLibs/x86_64/*      android/SherpaOnnxAar/sherpa_onnx/src/main/jniLibs/x86_64/

# Build AAR
cd android/SherpaOnnxAar && ./gradlew :sherpa_onnx:assembleRelease
# Output: sherpa_onnx/build/outputs/aar/sherpa_onnx-release.aar
```

**Gradle dependency** (local AAR via `fileTree`):

```kotlin
// app/build.gradle.kts
dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
}
```

Copy `sherpa_onnx-release.aar` into `app/libs/`. Pin the version in the filename (e.g. `sherpa-onnx-1.12.29.aar`) for reproducibility.

### `jniLibs/` ABI Layout

```
app/src/main/jniLibs/
├── arm64-v8a/      # 64-bit ARM  — required for modern devices and Play Store
├── armeabi-v7a/    # 32-bit ARM  — older devices
├── x86/            # 32-bit x86  — emulator
└── x86_64/         # 64-bit x86  — emulator
```

### Library Loading

```kotlin
companion object {
    init {
        System.loadLibrary("sherpa-onnx-jni")  // exact library name
    }
}
```

### Kotlin Interface for Testability

JNI-backed classes cannot be instantiated in JVM unit tests (no native library). Define an interface for every JNI engine so unit tests use a mock/fake:

```kotlin
// Interface — mockable in JVM tests
interface SpeechRecognizer {
    fun acceptWaveform(samples: FloatArray, sampleRate: Int)
    fun isEndpoint(): Boolean
    fun getResult(): String
    fun reset()
    fun release()
}

// Production implementation wrapping JNI
class SherpaRecognizer(config: OnlineRecognizerConfig) : SpeechRecognizer {
    private val recognizer = OnlineRecognizer(config = config)
    private val stream = recognizer.createStream()

    override fun acceptWaveform(samples: FloatArray, sampleRate: Int) =
        stream.acceptWaveform(samples, sampleRate)
    override fun isEndpoint() = recognizer.isEndpoint(stream)
    override fun getResult() = recognizer.getResult(stream).text
    override fun reset() = recognizer.reset(stream)
    override fun release() { stream.release(); recognizer.release() }
}

// Test fake — no JNI, runs in any JVM
class FakeSpeechRecognizer : SpeechRecognizer {
    override fun acceptWaveform(samples: FloatArray, sampleRate: Int) {}
    override fun isEndpoint() = true
    override fun getResult() = "test transcript"
    override fun reset() {}
    override fun release() {}
}
```

### Sherpa-ONNX Key Classes

| Class | Use |
|-------|-----|
| `OnlineRecognizer` | Streaming (real-time) ASR — `createStream()`, `decode()`, `isEndpoint()`, `getResult()` |
| `OfflineRecognizer` | Batch ASR — `createStream()`, `decode()`, `getResult()` |
| `OfflineTts` | TTS — `generate(text, sid, speed)`, `generateWithCallback(...)`, `sampleRate()` |
| `Vad` | Voice activity detection — `acceptWaveform()`, `isSpeechDetected()`, `front()` |
| `OnlineStream` / `OfflineStream` | Audio input buffer — use `.use {}` block for auto-cleanup |

### Piper ONNX TTS Integration

Sherpa-ONNX runs piper-format ONNX voice models via `OfflineTtsVitsModelConfig`. Models downloaded from `k2-fsa/sherpa-onnx` releases or `rhasspy/piper-voices` (HuggingFace):

```kotlin
val modelDir = "vits-piper-en_US-amy-low"

val ttsConfig = OfflineTtsConfig(
    model = OfflineTtsModelConfig(
        vits = OfflineTtsVitsModelConfig(
            model = "$modelDir/en_US-amy-low.onnx",
            tokens = "$modelDir/tokens.txt",
            dataDir = "$modelDir/espeak-ng-data",  // required for piper models
        ),
        numThreads = 4,
        provider = "cpu",
    ),
)

val tts = OfflineTts(assetManager = assets, config = ttsConfig)
val audio: GeneratedAudio = tts.generate(text = "Hello world", sid = 0, speed = 1.0f)
// audio.samples: FloatArray, audio.sampleRate: Int
// Feed to AudioTrack for playback
```

**Do not reference `piper1-gpl` (`OHF-Voice/piper1-gpl`)** — it is GPL v3, has no Android support, and cannot produce an AAR. Sherpa-ONNX runs the same model format under Apache 2.0.

## Matrix Client

mautrix is a **server-side framework only** — there is no mautrix Android SDK. Android clients connect to any Matrix homeserver (including Tuwunel) using the standard Matrix CS API:

- **matrix-rust-sdk** Kotlin bindings: the recommended modern client. Provides E2EE, sync, and room management. Check the project's releases for current AAR/Maven coordinates.
- Connects via standard `/_matrix/client/` API endpoints — fully compatible with Tuwunel and all Conduit-family homeservers.

## Android Keystore

- **`EncryptedSharedPreferences`** for URL/config storage (e.g. homeserver URL, display name):

```kotlin
val masterKey = MasterKey.Builder(context)
    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
    .build()
val prefs = EncryptedSharedPreferences.create(
    context, "app_prefs", masterKey,
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
)
```

- **`KeyStore` + `KeyPairGenerator`** for Matrix access tokens (asymmetric — tokens encrypted at rest):

```kotlin
val keyPairGenerator = KeyPairGenerator.getInstance(
    KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore"
)
keyPairGenerator.initialize(
    KeyGenParameterSpec.Builder("matrix_token_key",
        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
        .setDigests(KeyProperties.DIGEST_SHA256)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .setIsStrongBoxBacked(true)   // hardware-backed (API 28+)
        .build()
)
```

- **StrongBox fallback**: `setIsStrongBoxBacked(true)` throws `StrongBoxUnavailableException` on devices without a Secure Element. Always catch and retry without it:

```kotlin
fun generateKey(alias: String): Boolean {
    return try {
        generateKeyWithStrongBox(alias)
        true
    } catch (e: StrongBoxUnavailableException) {
        generateKeySoftwareBacked(alias)  // falls back to TEE/software
        false
    }
}
```

## Bluetooth Headset Audio

```kotlin
// Manifest
// <uses-permission android:name="android.permission.RECORD_AUDIO" />
// <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

// BroadcastReceiver for headset button
class HeadsetButtonReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MEDIA_BUTTON) return
        val event = intent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT) ?: return
        if (event.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            && event.action == KeyEvent.ACTION_DOWN) {
            // toggle recording
        }
    }
}

// Route audio to Bluetooth SCO headset
val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
audioManager.startBluetoothSco()
audioManager.isBluetoothScoOn = true

// Background audio capture requires a foreground Service with MICROPHONE type
class AudioCaptureService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()  // required
        startForeground(NOTIFICATION_ID, notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        return START_STICKY
    }
}
```

Register the receiver with `MEDIA_CONTENT_TYPE` priority and include `<intent-filter>` for `ACTION_MEDIA_BUTTON` in `AndroidManifest.xml`.

## F-Droid Build Requirements

- **No Google Play Services** — no `com.google.android.gms`, Firebase, or proprietary SDKs. Verify with `./gradlew dependencies | grep gms`.
- **Reproducible builds** in `app/build.gradle.kts`:

```kotlin
android {
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}
```

- **`fastlane/metadata/android/`** directory structure:

```
fastlane/metadata/android/
└── en-US/
    ├── title.txt                  # App name (max 30 chars)
    ├── short_description.txt      # One-line description (max 80 chars)
    ├── full_description.txt       # Full description (max 4000 chars)
    └── changelogs/
        └── <versionCode>.txt      # Release notes for each version code
```

- `versionCode` in `build.gradle.kts` must increment monotonically. `versionName` is the human-readable string.
- No `latest` or `+` version wildcards — F-Droid requires reproducible, deterministic dependency resolution.

## CI (GitHub Actions)

```yaml
name: CI
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17

      - name: Lint
        run: ./gradlew lint

      - name: Unit tests   # JVM only — no emulator required
        run: ./gradlew test

      - name: Assemble debug APK
        run: ./gradlew assembleDebug
```

Unit tests run on the JVM and must not invoke JNI — mock all native engines via the interface pattern above. Instrumented tests (`androidTest`) require a device or emulator and run separately.

## Anti-patterns

- **Google Play Services dependency** — any `com.google.android.gms` transitive dep blocks F-Droid distribution. Audit with `./gradlew dependencies`.
- **JNI calls in JVM unit test scope** — `OnlineRecognizer`, `OfflineTts`, etc. cannot load their native library in a JVM test. Always put JNI behind an interface and inject a fake in tests.
- **Hardcoded server URLs** — configure homeserver URL at runtime via `EncryptedSharedPreferences`; never compile it into the APK.
- **`SharedPreferences` for Matrix tokens** — unencrypted; use `EncryptedSharedPreferences` or `KeyStore`-backed storage.
- **`latest` / `+` version on AAR** — non-reproducible builds; F-Droid rejects them. Pin Sherpa-ONNX by exact version in the AAR filename.
- **`BroadcastReceiver` without foreground Service** — background audio capture fails on API 26+ without a foreground Service declaring `FOREGROUND_SERVICE_TYPE_MICROPHONE`.
- **Skipping StrongBox fallback** — `setIsStrongBoxBacked(true)` throws `StrongBoxUnavailableException` on devices without a Secure Element (most non-Pixel hardware). Always catch and retry software-backed.
- **Referencing piper1-gpl for Android** — GPL v3, no Android AAR, no JNI bridge, no NDK toolchain support. Use Sherpa-ONNX with piper ONNX model files instead.
