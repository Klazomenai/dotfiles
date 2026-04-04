---
name: android
description: >-
  Android/Kotlin development — Gradle Kotlin DSL, JNI/AAR native library
  integration (Sherpa-ONNX for ASR and TTS with piper ONNX models), matrix-rust-sdk
  Kotlin bindings (Sliding Sync, E2EE, session persistence), Android Keystore
  credential storage, Bluetooth headset audio, onboarding wizard patterns,
  ActivityResultContracts runtime permissions, and F-Droid reproducible build
  requirements. Use when writing Android/Kotlin code, reviewing Android PRs,
  or configuring Gradle/JNI tooling.
---

# Android Skill

## Project Structure

- Gradle Kotlin DSL (`build.gradle.kts`) as the single build config format — no Groovy `.gradle` files.
- Standard module layout: `app/src/main/` (production), `app/src/test/` (JVM unit tests), `app/src/androidTest/` (instrumented tests on device/emulator).
- Minimum SDK: **API 28** (Android 9) for StrongBox Keystore hardware backing. Sherpa-ONNX supports minSdk 21 — keep app minSdk at 28 for Keystore guarantees.
- `settings.gradle.kts` defines `dependencyResolutionManagement.repositories`; do not add repo declarations in module-level `build.gradle.kts`.
- `gradle/libs.versions.toml` (version catalog) for all dependency version pins — single source of truth, prevents drift.

### Version Catalog Hygiene

- Always use `version.ref` in library entries — never inline `version = "x.y.z"` (causes duplication with the `[versions]` section).
- JitPack versions may require a `v` prefix (e.g. `sherpaOnnx = "v1.12.29"`) — this matches upstream git tags.
- Verify versions against cloned upstream repos, not internet searches. Clone the repo, read `gradle.properties`, `CMakeLists.txt`, or `Cargo.toml` for the authoritative version.
- Upstream version sources vary: Sherpa-ONNX versions are in `CMakeLists.txt`, matrix-rust-sdk Android bindings are in `matrix-org/matrix-rust-components-kotlin/buildSrc/src/main/kotlin/BuildVersionsSDK.kt`.

## Native Library Integration (JNI/AAR) — Sherpa-ONNX

Sherpa-ONNX (`com.github.k2-fsa:sherpa-onnx`) is the primary library for on-device ASR and TTS. It runs piper-format ONNX voice models natively on Android with an Apache 2.0 license.

**Sherpa-ONNX is published via JitPack** (not Maven Central). The version requires a `v` prefix matching upstream git tags. Scope the JitPack repository to only the Sherpa-ONNX group:

```kotlin
// settings.gradle.kts — scope JitPack to Sherpa-ONNX only (supply-chain hygiene)
maven {
    url = uri("https://jitpack.io")
    content {
        includeGroup("com.github.k2-fsa")
    }
}
```

```kotlin
// Option A — JitPack (simplest; verify version against cloned k2-fsa/sherpa-onnx repo)
implementation("com.github.k2-fsa:sherpa-onnx:v1.12.29")  // note: 'v' prefix required
```

Build from source (Option B — local AAR, required for F-Droid or custom ABI sets):

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

**Gradle dependency** (local AAR — single pinned file, not `fileTree`):

```kotlin
// app/build.gradle.kts
dependencies {
    // Use a single pinned files() entry, not fileTree("*.aar").
    // fileTree globs every AAR in libs/, which can accidentally include old/duplicate
    // versions and makes builds non-deterministic.
    implementation(files("libs/sherpa-onnx-1.12.29.aar"))
}
```

Copy `sherpa_onnx-release.aar` into `app/libs/` and rename to the versioned filename (e.g. `sherpa-onnx-1.12.29.aar`). Update the `files(...)` path when upgrading.

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

### OfflineRecognizer (Batch/Offline STT)

For short utterances (voice commands), use `OfflineRecognizer` with `OfflineWhisperModelConfig`. Unlike `OnlineRecognizer`, there is no `isEndpoint()` or `reset()` — feed the complete audio and decode once:

```kotlin
interface SttEngine {
    suspend fun transcribe(audioFile: File): String
    fun close()
}

class SherpaOnnxSttEngine(private val context: Context) : SttEngine {
    private var recognizerInstance: OfflineRecognizer? = null

    private val recognizer: OfflineRecognizer
        get() = recognizerInstance ?: createRecognizer().also { recognizerInstance = it }

    // Copy ONNX models + tokens from assets/ to filesDir/ (JNI needs file-system paths).
    // Check for specific files (not just non-empty dir) to detect partial copies.
    private fun copyAssetsToDisk(): File {
        val destDir = File(context.filesDir, "stt")
        val encoderOk = File(destDir, "tiny.en-encoder.int8.onnx").let { it.exists() && it.length() > 0 }
        val decoderOk = File(destDir, "tiny.en-decoder.int8.onnx").let { it.exists() && it.length() > 0 }
        val tokensOk = File(destDir, "tiny.en-tokens.txt").let { it.exists() && it.length() > 0 }
        if (destDir.exists() && encoderOk && decoderOk && tokensOk) return destDir
        destDir.mkdirs()
        context.assets.list("stt")?.forEach { name ->
            context.assets.open("stt/$name").use { src ->
                FileOutputStream(File(destDir, name)).use { out -> src.copyTo(out) }
            }
        }
        return destDir
    }

    private fun createRecognizer(): OfflineRecognizer {
        val sttDir = copyAssetsToDisk().absolutePath
        val config = OfflineRecognizerConfig(
            featConfig = FeatureConfig(sampleRate = 16000, featureDim = 80),
            modelConfig = OfflineModelConfig(
                whisper = OfflineWhisperModelConfig(
                    encoder = "$sttDir/tiny.en-encoder.int8.onnx",
                    decoder = "$sttDir/tiny.en-decoder.int8.onnx",
                    language = "en",
                    task = "transcribe",
                ),
                // tokens is REQUIRED — validation fails silently (returns null
                // pointer) without it, causing SIGSEGV on createStream().
                tokens = "$sttDir/tiny.en-tokens.txt",
                numThreads = 2, debug = false, provider = "cpu",
            ),
        )
        return OfflineRecognizer(config = config)
    }

    override suspend fun transcribe(audioFile: File): String = withContext(Dispatchers.IO) {
        val stream = recognizer.createStream()
        try {
            val bytes = audioFile.readBytes()
            val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            val samples = FloatArray(bytes.size / 2) { buf.short / 32768f }
            stream.acceptWaveform(samples, 16000)
            recognizer.decode(stream)
            recognizer.getResult(stream).text
        } finally { stream.release() }
    }

    // Idempotent — nullable instance avoids lazy-init on close()
    override fun close() { recognizerInstance?.release(); recognizerInstance = null }
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

## Matrix Client (matrix-rust-sdk)

mautrix is a **server-side framework only** — there is no mautrix Android SDK. Android clients use the matrix-rust-sdk Kotlin bindings (UniFFI-generated). See the [Matrix skill](../matrix/SKILL.md) for protocol and E2EE concepts.

- **Artifact**: `org.matrix.rustcomponents:sdk-android` on Maven Central. No extra repository needed.
- **Version source**: Android bindings version (e.g. `26.03.19`) comes from `matrix-org/matrix-rust-components-kotlin`, NOT from `matrix-rust-sdk` itself (which uses FFI crate versioning like `0.16.0`).
- **Sliding Sync only**: The SDK only exposes `SyncService` (Simplified Sliding Sync / MSC4186). Traditional `/sync` v2 is NOT available through the FFI. Use `SlidingSyncVersionBuilder.DISCOVER_NATIVE`.
- **E2EE is automatic** when a SQLite store is configured via `sessionPaths()`. No explicit key management for basic usage.

### ClientBuilder and Login

All SDK calls marked `suspend` must run in a coroutine scope (e.g. `withContext(Dispatchers.IO) { ... }`).

```kotlin
import org.matrix.rustcomponents.sdk.*
import java.io.File

val dataDir = File(context.filesDir, "matrix-data").apply { mkdirs() }
val cacheDir = File(context.cacheDir, "matrix-cache").apply { mkdirs() }

val client = ClientBuilder()
    .homeserverUrl("https://matrix.example.com")
    .slidingSyncVersionBuilder(SlidingSyncVersionBuilder.DISCOVER_NATIVE)
    .sessionPaths(dataDir.absolutePath, cacheDir.absolutePath)
    .build()  // suspend

client.login(username, password, "MyApp Android", null)  // suspend

// Persist session for later restore
val session: Session = client.session()
// Session fields: accessToken, refreshToken?, userId, deviceId, homeserverUrl,
//                 oidcData?, slidingSyncVersion
```

### Session Restore

```kotlin
val client = ClientBuilder()
    .homeserverUrl(savedHomeserverUrl)
    .slidingSyncVersionBuilder(SlidingSyncVersionBuilder.DISCOVER_NATIVE)
    .sessionPaths(dataDir.absolutePath, cacheDir.absolutePath)
    .build()  // suspend

client.restoreSession(savedSession)  // suspend
```

Store `Session` fields in `EncryptedSharedPreferences` / Android Keystore (see Keystore section below). The SQLite store at `sessionPaths` persists E2EE keys — do NOT delete it between restarts.

### Sync and Timeline

```kotlin
// Start Sliding Sync
val syncService = client.syncService().finish()
syncService.start()  // suspend — begins background sync

// IMPORTANT: getRoom() returns null until Sliding Sync delivers the room.
// Use retry with backoff — see "Sliding Sync Readiness" section below.
val room = awaitRoom(client, roomId)
val timeline = room.timeline()  // suspend

val handle = timeline.addListener(object : TimelineListener {
    override fun onUpdate(diff: List<TimelineDiff>) {
        for (d in diff) {
            val items = when (d) {
                is TimelineDiff.Append -> d.values
                is TimelineDiff.PushBack -> listOf(d.value)
                else -> emptyList()
            }
            items.forEach { processItem(it) }
        }
    }
})

// Stop sync
syncService.stop()
handle.close()
```

### Sliding Sync Readiness

`client.getRoom(roomId)` returns **null before Sliding Sync delivers rooms**. After `login()` or `restoreSession()`, the state store is empty. Rooms are populated asynchronously by the `SyncService` background loop. Calling `getRoom()` immediately after `syncService.start()` is a race condition.

**Callback interfaces for sync state observation:**

| Interface | States | When rooms are available |
|-----------|--------|------------------------|
| `SyncServiceStateObserver` | `IDLE`, `RUNNING`, `TERMINATED`, `ERROR`, `OFFLINE` | After `RUNNING` |
| `RoomListServiceStateListener` | `INITIAL`, `SETTING_UP`, `RECOVERING`, `RUNNING`, `ERROR`, `TERMINATED` | After `RUNNING` |
| `RoomListLoadingStateListener` | `NotLoaded`, `Loaded(maximumNumberOfRooms)` | After `Loaded` |

**Correct pattern — observe room list state before `getRoom()`:**

```kotlin
import org.matrix.rustcomponents.sdk.RoomListServiceState
import org.matrix.rustcomponents.sdk.RoomListServiceStateListener

val syncService = client.syncService().finish()
syncService.start()

// Observe room list readiness
val roomListService = syncService.roomListService()
val stateHandle = roomListService.state(object : RoomListServiceStateListener {
    override fun onUpdate(state: RoomListServiceState) {
        if (state == RoomListServiceState.RUNNING) {
            // Rooms are now available — safe to call getRoom()
        }
    }
})
// Keep stateHandle alive; call stateHandle.cancel() on cleanup
```

**Pragmatic alternative — retry with backoff:**

When the interface contract doesn't support async readiness (e.g. existing `MatrixClient` abstraction), retry `getRoom()` with exponential backoff. Must run in a coroutine context (`delay` is a suspend function):

```kotlin
import kotlinx.coroutines.delay
import org.matrix.rustcomponents.sdk.Client
import org.matrix.rustcomponents.sdk.Room

suspend fun awaitRoom(client: Client, roomId: String): Room {
    val delays = longArrayOf(100, 200, 500, 1000, 2000, 5000)
    for (attempt in delays.indices) {
        val room = client.getRoom(roomId)
        if (room != null) return room
        if (attempt < delays.lastIndex) {
            // Log retry attempts so the user sees progress
            delay(delays[attempt])
        }
    }
    throw IllegalArgumentException("Room not found after ${delays.size} attempts: $roomId")
}
```

Total max wait: ~3.8 seconds (100+200+500+1000+2000; final attempt has no delay). Typically succeeds on first or second attempt (~100-300ms). Log each retry so the user sees progress.

### Message Extraction

```kotlin
fun processItem(item: TimelineItem) {
    val event = item.asEvent() ?: return
    if (event.isOwn) return  // self-filter
    val content = event.content
    if (content !is TimelineItemContent.MsgLike) return
    val kind = content.content.kind
    if (kind !is MsgLikeKind.Message) return
    val msgType = kind.content.msgType
    if (msgType !is MessageType.Text) return
    val body = msgType.content.body  // the message text
    // process body...
}
```

### Sending Messages

```kotlin
// sendRaw for custom event fields or standard m.room.message
room.sendRaw("m.room.message", """{"msgtype":"m.text","body":"hello"}""")
```

Use `Room.sendRaw(eventType, contentJson)` — the typed `Timeline.send()` API works but `sendRaw` is simpler for JSON payloads.

### Custom Event Fields Limitation

The SDK's typed API (`TextMessageContent`) strips custom JSON fields from event content during Rust→Kotlin conversion. Only `body` and `formatted` are accessible. For custom metadata (e.g. crew member, verbosity), use a body-prefix convention:

```
[crewname:verbosity] response text here
```

Parse with a regex on the receiving side. Proper raw event access is a future improvement.

### ProGuard Rules (matrix-rust-sdk)

The SDK uses JNA for the native bridge. Its `consumer-rules.pro` is empty — add these to the app's `proguard-rules.pro`:

```
# JNA — transitive dependency of org.matrix.rustcomponents:sdk-android.
# Package is com.sun.jna (NOT net.java.dev.jna — that's the Maven group ID).
-keep class com.sun.jna.** { *; }
-keep class org.matrix.rustcomponents.sdk.** { *; }
-keep class uniffi.** { *; }

# JNA's Native$AWT references java.awt classes not available on Android.
# These code paths are never reached (JNA detects Android at runtime).
-dontwarn java.awt.**
```

Also keep any app classes implementing SDK callback interfaces (`TimelineListener`, `SyncServiceStateObserver`, `RoomListServiceStateListener`, etc.).

### JVM Heap for Large SDKs

The UniFFI-generated Kotlin file is ~60K lines. Combined with Sherpa-ONNX, the default JVM metaspace (256m) is insufficient for CI builds. Add to `gradle.properties`:

```properties
org.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m
```

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

- **`KeyStore` + `KeyGenerator`** for Matrix access tokens (AES-GCM symmetric key — tokens encrypted at rest):

```kotlin
// EC keys in Android Keystore support signing/verification only, not encryption.
// For encrypting tokens at rest, use AES-GCM; store ciphertext + IV in prefs.
//
// setIsStrongBoxBacked(true) throws StrongBoxUnavailableException on devices without
// a Secure Element (most non-Pixel hardware). Never call unconditionally — use the
// helper below which falls back to software-backed TEE automatically.
fun buildKeySpec(alias: String, strongBox: Boolean): KeyGenParameterSpec =
    KeyGenParameterSpec.Builder(alias,
        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
        .setKeySize(256)
        .apply { if (strongBox) setIsStrongBoxBacked(true) }
        .build()

// Returns a hardware-backed key where available; falls back to TEE/software silently.
fun generateAesKey(alias: String): SecretKey {
    val kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
    return try {
        kg.init(buildKeySpec(alias, strongBox = true))
        kg.generateKey()
    } catch (e: StrongBoxUnavailableException) {
        kg.init(buildKeySpec(alias, strongBox = false))
        kg.generateKey()
    }
}
val secretKey = generateAesKey("matrix_token_key")

// Encrypt token → store Base64(ciphertext) + Base64(IV) in EncryptedSharedPreferences
fun encryptToken(token: String, key: SecretKey): Pair<ByteArray, ByteArray> {
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, key)
    // Use explicit UTF-8 charset — platform default varies by locale/device.
    return cipher.doFinal(token.toByteArray(Charsets.UTF_8)) to cipher.iv
}
```

## Bluetooth Headset Audio

Required manifest entries:

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- API 34+: explicit foreground service permission for microphone capture -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />

<application>
    <!-- Declare foreground service type in the manifest for API 29+ -->
    <service android:name=".AudioCaptureService"
        android:foregroundServiceType="microphone" />

    <!-- Register the media button receiver with priority so it receives events
         before the default system handler. Use android:priority on intent-filter.
         android:exported="true" is required for targetSdk 31+ when an intent-filter
         is present; omitting it causes a build-time manifest validation failure. -->
    <receiver android:name=".HeadsetButtonReceiver"
        android:exported="true">
        <intent-filter android:priority="100">
            <action android:name="android.intent.action.MEDIA_BUTTON" />
        </intent-filter>
    </receiver>
</application>
```

```kotlin
// BroadcastReceiver for headset button
class HeadsetButtonReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MEDIA_BUTTON) return
        // getParcelableExtra(String) is deprecated on API 33+; use the typed overload.
        val event: KeyEvent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
        }
        event ?: return
        if (event.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            && event.action == KeyEvent.ACTION_DOWN) {
            // toggle recording
        }
    }
}

// Route audio to Bluetooth SCO headset.
// BLUETOOTH_CONNECT (API 31+) is a runtime permission — request it before querying
// Bluetooth devices. availableCommunicationDevices returns an empty list (and
// setCommunicationDevice is a no-op) if the permission has not been granted.
// Check with: ActivityCompat.checkSelfPermission(ctx, Manifest.permission.BLUETOOTH_CONNECT)
val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    // API 31+: use setCommunicationDevice with USAGE_VOICE_COMMUNICATION
    val btDevice = audioManager.availableCommunicationDevices
        .firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
    if (btDevice != null) {
        audioManager.setCommunicationDevice(btDevice)
        // When finished: audioManager.clearCommunicationDevice()
    }
} else {
    // API ≤ 30: legacy SCO path — ensure the service is in communication mode first
    @Suppress("DEPRECATION")
    audioManager.startBluetoothSco()
    @Suppress("DEPRECATION")
    audioManager.isBluetoothScoOn = true
    // When finished: audioManager.stopBluetoothSco(); audioManager.isBluetoothScoOn = false
}

// Background audio capture requires a foreground Service with MICROPHONE type.
// The manifest must also declare android:foregroundServiceType="microphone" on the
// <service> element (API 29+) and FOREGROUND_SERVICE_MICROPHONE permission (API 34+).
class AudioCaptureService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()  // required
        // 3-arg startForeground(id, notification, type) requires API 29+.
        // minSdk 28 devices must use the 2-arg overload — gate on SDK version.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }
}
```

For reliable media button handling (e.g. play/pause on a Bluetooth headset), prefer registering a `MediaSession` and setting `setCallback` — the system routes `ACTION_MEDIA_BUTTON` to the active `MediaSession` automatically on API 21+, without needing a manifest receiver.

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
on:
  push:
    branches: [main]    # CI on push to main
  pull_request:          # CI on PRs — do NOT use [push, pull_request] (fires twice on PR branches)

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

## Onboarding / Wizard Patterns

For apps without Fragments (e.g. single-Activity architectures), a view-swapping step wizard is simpler than ViewPager2/NavGraph. Single Activity with `FrameLayout` containing `<include>` layouts, toggled via `View.VISIBLE`/`View.GONE`:

```kotlin
class OnboardingActivity : AppCompatActivity() {
    private var currentStep = 0
    private lateinit var stepViews: List<View>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_onboarding)

        stepViews = listOf(
            findViewById(R.id.step_login),
            findViewById(R.id.step_voice),
            findViewById(R.id.step_permissions),
        )

        // Restore step across config changes (rotation, etc.)
        if (savedInstanceState != null) {
            currentStep = savedInstanceState
                .getInt(KEY_CURRENT_STEP, 0)
                .coerceIn(0, stepViews.lastIndex)
        }
        showStep(currentStep)

        // Modern back navigation — replaces deprecated onBackPressed()
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (currentStep > 0) { currentStep--; showStep(currentStep) }
                else finish()
            }
        })

        findViewById<Button>(R.id.btn_next).setOnClickListener { goNext() }
    }

    private fun showStep(step: Int) {
        stepViews.forEachIndexed { i, view ->
            view.visibility = if (i == step) View.VISIBLE else View.GONE
        }
        // Update step indicator, back button visibility, next button text
        findViewById<Button>(R.id.btn_next).text =
            if (step == stepViews.lastIndex) "Finish" else "Next"
    }

    private fun goNext() {
        when (currentStep) {
            STEP_LOGIN -> validateAndLogin()       // per-step validation
            STEP_VOICE -> advanceStep()
            STEP_PERMISSIONS -> advanceStep()
        }
    }

    private fun advanceStep() {
        if (currentStep < stepViews.lastIndex) {
            currentStep++
            showStep(currentStep)
        } else {
            setResult(RESULT_OK)
            finish()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt(KEY_CURRENT_STEP, currentStep)
    }

    companion object {
        private const val KEY_CURRENT_STEP = "current_step"
        private const val STEP_LOGIN = 0
        private const val STEP_VOICE = 1
        private const val STEP_PERMISSIONS = 2
    }
}
```

### Coroutine Login with Inline Progress/Error

Validate inputs before launching the coroutine. Disable the submit button and show a `ProgressBar` during the network call. Re-throw `CancellationException` — swallowing it breaks structured concurrency:

```kotlin
private fun validateAndLogin() {
    val url = homeserverInput.text.toString().trim()
    val username = usernameInput.text.toString().trim()
    val password = passwordInput.text.toString().trim()

    if (url.isEmpty()) { homeserverInput.error = "Required"; return }
    if (!url.startsWith("https://")) { homeserverInput.error = "Must start with https://"; return }
    if (username.isEmpty()) { usernameInput.error = "Required"; return }
    if (password.isEmpty()) { passwordInput.error = "Required"; return }

    loginProgress.visibility = View.VISIBLE
    loginError.visibility = View.GONE
    btnNext.isEnabled = false

    lifecycleScope.launch {
        try {
            withContext(Dispatchers.IO) {
                client.login(url, username, password)
            }
            advanceStep()
        } catch (e: CancellationException) {
            throw e  // never swallow — breaks structured concurrency
        } catch (e: Exception) {
            loginError.text = e.message ?: "Login failed"
            loginError.visibility = View.VISIBLE
        } finally {
            loginProgress.visibility = View.GONE
            btnNext.isEnabled = true
        }
    }
}
```

## Runtime Permissions (ActivityResultContracts)

The modern permission API (`registerForActivityResult`) replaces the deprecated `onRequestPermissionsResult` callback. Register launchers during initialization **before** the `Activity` or `Fragment` reaches `STARTED` (for example, at class level or in `onCreate()`); registering from post-init callbacks such as `onClick`, `onResume`, or any `STARTED`/later state throws `IllegalStateException`.

```kotlin
class OnboardingActivity : AppCompatActivity() {
    // Register at class level — NEVER inside onClick or other callbacks
    private val requestAudioPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        updatePermissionStatus()
        if (!granted) {
            handlePermanentDenial(Manifest.permission.RECORD_AUDIO)
        }
    }

    private val requestBluetoothPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        updatePermissionStatus()
        if (!granted) {
            handlePermanentDenial(Manifest.permission.BLUETOOTH_CONNECT)
        }
    }
```

### Requesting Permissions

Use the `launchPermissionRequest()` helper (defined in "Detecting Permanent Denial" below) so the `wasPermissionRequested` flag is set before every launch:

```kotlin
// Audio — all API levels
btnGrantAudio.setOnClickListener {
    launchPermissionRequest(
        Manifest.permission.RECORD_AUDIO,
        requestAudioPermission,
    )
}

// Bluetooth — API 31+ only (BLUETOOTH_CONNECT is a new runtime permission)
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    btnGrantBluetooth.setOnClickListener {
        launchPermissionRequest(
            Manifest.permission.BLUETOOTH_CONNECT,
            requestBluetoothPermission,
        )
    }
} else {
    // Pre-Android 12: BLUETOOTH_CONNECT doesn't exist; legacy permissions
    // are install-time only (declared in manifest with maxSdkVersion="30")
    btnGrantBluetooth.isEnabled = false
    bluetoothStatus.text = "Not required (API < 31)"
}
```

### Checking Permission State

```kotlin
private fun updatePermissionStatus() {
    val audioGranted = ContextCompat.checkSelfPermission(
        this, Manifest.permission.RECORD_AUDIO,
    ) == PackageManager.PERMISSION_GRANTED

    audioStatus.text = if (audioGranted) "Granted" else "Not granted"
    btnGrantAudio.isEnabled = !audioGranted

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val btGranted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
        bluetoothStatus.text = if (btGranted) "Granted" else "Not granted"
        btnGrantBluetooth.isEnabled = !btGranted
    }
}
```

### Detecting Permanent Denial

`shouldShowRequestPermissionRationale()` returns `false` in three cases: (a) before the first request, (b) after the user selects "Don't ask again", (c) when already granted. Only treat it as permanent denial if the permission is currently denied **and** has been requested at least once. Persist a flag when launching the request so the check survives process death:

```kotlin
private val prefs by lazy {
    getSharedPreferences("permissions", MODE_PRIVATE)
}

private fun launchPermissionRequest(
    permission: String,
    launcher: ActivityResultLauncher<String>,
) {
    // Set flag before launching — persists across process death
    prefs.edit().putBoolean("${permission}_requested", true).commit()
    launcher.launch(permission)
}

private fun handlePermanentDenial(permission: String) {
    val wasRequested = prefs.getBoolean("${permission}_requested", false)
    val permissionDenied = ContextCompat.checkSelfPermission(
        this, permission,
    ) != PackageManager.PERMISSION_GRANTED

    if (permissionDenied &&
        wasRequested &&
        !ActivityCompat.shouldShowRequestPermissionRationale(this, permission)
    ) {
        // Permission denied after at least one request and no rationale available —
        // direct user to app Settings
        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
        })
    }
}
```

## Anti-patterns

- **Google Play Services dependency** — any `com.google.android.gms` transitive dep blocks F-Droid distribution. Audit with `./gradlew dependencies`.
- **JNI calls in JVM unit test scope** — `OnlineRecognizer`, `OfflineTts`, etc. cannot load their native library in a JVM test. Always put JNI behind an interface and inject a fake in tests.
- **Hardcoded server URLs** — configure homeserver URL at runtime via `EncryptedSharedPreferences`; never compile it into the APK.
- **`SharedPreferences` for Matrix tokens** — unencrypted; use `EncryptedSharedPreferences` or `KeyStore`-backed storage.
- **`latest` / `+` version on AAR** — non-reproducible builds; F-Droid rejects them. Pin Sherpa-ONNX by exact version in the AAR filename.
- **`BroadcastReceiver` without foreground Service** — background audio capture fails on API 26+ without a foreground Service declaring `FOREGROUND_SERVICE_TYPE_MICROPHONE`.
- **Skipping StrongBox fallback** — `setIsStrongBoxBacked(true)` throws `StrongBoxUnavailableException` on devices without a Secure Element (most non-Pixel hardware). Always catch and retry software-backed.
- **Referencing piper1-gpl for Android** — GPL v3, no Android AAR, no JNI bridge, no NDK toolchain support. Use Sherpa-ONNX with piper ONNX model files instead.
- **`on: [push, pull_request]` CI trigger** — fires CI twice on every push to a branch with an open PR. Scope push to `main` only: `on: { push: { branches: [main] }, pull_request: }`.
- **Unscoped JitPack repository** — `maven { url = uri("https://jitpack.io") }` without `content { includeGroup(...) }` expands the supply-chain trust boundary to all of JitPack. Always scope to the specific group needed.
- **Inline `version = "x.y.z"` in version catalog** — duplicates the version with the `[versions]` section. Always use `version.ref`.
- **Assuming `/sync` v2 availability** — matrix-rust-sdk FFI only exposes Sliding Sync via `SyncService`. Do not attempt to call `Client.sync()` or use traditional sync endpoints.
- **Custom event fields via typed SDK API** — `TextMessageContent` strips custom JSON fields during Rust→Kotlin conversion. Use `Room.sendRaw()` for sending custom fields and body-prefix convention for receiving.
- **Missing ProGuard rules for JNA/UniFFI** — release builds crash without keep rules for `com.sun.jna.**` (NOT `net.java.dev.jna.**` — that's the Maven group ID), `org.matrix.rustcomponents.sdk.**`, `uniffi.**`. Also needs `-dontwarn java.awt.**` for JNA's desktop AWT refs. The SDK's `consumer-rules.pro` is empty.
- **Deleting `sessionPaths` SQLite store** — the store persists E2EE keys (Olm sessions, Megolm keys). Deleting it loses all encryption state and requires full session reset.
- **Calling `getRoom()` before Sliding Sync delivers rooms** — returns null immediately after `login()` or `restoreSession()`. Wait for `RoomListServiceState.RUNNING` or use retry with backoff. See "Sliding Sync Readiness" section.
- **Missing Whisper tokens file** — `OfflineModelConfig.tokens` must point to `tiny.en-tokens.txt`. Without it, `OfflineRecognizer` native constructor returns null (0) and `createStream()` dereferences it → SIGSEGV. Validation fails silently at `offline-model-config.cc:101-106`.
- **Registering `ActivityResultContracts` inside callbacks** — `registerForActivityResult()` must be called during Activity/Fragment initialization (before `STARTED` state). Calling it inside `onClick`, `onResume`, or any other post-init callback throws `IllegalStateException`. Register launchers during initialization, either as class members/properties or early in `onCreate()`.
