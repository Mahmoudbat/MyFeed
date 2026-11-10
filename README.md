# MyFeed

Application ID: `com.imle.myfeed`

An offline, Android-first media app: browse your gallery as a feed, watch your
videos as reels, and keep private photos and videos in an encrypted locked
gallery.

## Features

1. **Gallery** – paged grid of all photos and videos, sortable by date or name.
2. **Reels** – vertical, shuffled feed of every video on the device.
3. **Albums** – your device albums.
4. **Locked gallery** – encrypted private space with its own feed, reels and albums.
5. Full-screen viewer with vertical or horizontal swiping, zoom, and video controls.

## Locked gallery security model

- Each file is encrypted with **AES-256-GCM** in 512 KiB chunks. Every chunk has
  a fresh random nonce and is bound to its position, so tampering, reordering
  and truncation are detected.
- A random 256-bit data key encrypts everything. It is stored only **wrapped**
  by a key derived from your password (PBKDF2-HMAC-SHA256, 600,000 iterations,
  random salt). The password itself is never stored, so **a forgotten password
  cannot be recovered**. You can only reset (erase) the locked gallery.
- File names on disk are random ids. Names, types, dates and albums live in an
  encrypted index.
- Videos are decrypted on the fly and streamed to the player over a
  token-protected loopback (127.0.0.1) socket, so no plaintext copies are
  written to disk. This is the only reason the app requests the `INTERNET`
  permission; it makes no outside connections.
- The vault locks after a configurable background delay (15 seconds by default).
  Choose Immediately, 5–55 seconds in five-second steps, or Off under Settings →
  Auto-lock delay or Locked Gallery Settings. Off keeps the vault unlocked when
  switching apps. Returning before the deadline cancels the countdown; manual
  locking and closing the app completely still lock immediately. While it is
  open, screenshots and the recent-apps preview are blocked (`FLAG_SECURE`).
- Repeated wrong passwords trigger an increasing lockout.
- Optional biometric unlock keeps a copy of the data key in Android
  Keystore-backed secure storage, released after a biometric check. This is
  more convenient but weaker than password-only.
- App data is excluded from cloud backups and device-to-device transfer.
- By default, moving items into the locked gallery removes the originals from the
  public gallery (Android asks you to confirm). Without that, nothing is hidden.

## Development

```bash
git clone git@github.com:Mahmoudbat/MyFeed.git
cd MyFeed
flutter pub get
flutter test      # unit tests: crypto format, vault store, media server
flutter run
```

### Build modes

| Command | App ID | Signed with |
|---|---|---|
| `flutter run` / `flutter build apk --debug` | `com.imle.myfeed.debug` ("MyFeed (debug)") | auto-generated debug key |
| `flutter build apk --release` | `com.imle.myfeed` ("MyFeed") | your release key |

Debug builds have their own separate ID to not replace (delete) real app data.

### Release signing

Release builds need `android/key.properties` (git-ignored):

```properties
storeFile=/absolute/path/to/myfeed-release.jks
storePassword=...
keyAlias=myfeed
keyPassword=...
```

Without it, release builds fail on purpose rather than falling back to the debug
key. Back up the keystore and its password: updates only install over an app
signed with the same key, and the alternative (uninstalling) erases the vault.

### Installing or updating a release build

Choose either method:

#### Option 1: Install the APK on your phone

1. Open the [latest release](https://github.com/Mahmoudbat/MyFeed/releases/latest).
2. Download the APK to your Android device.
3. Open the downloaded APK and follow Android's prompts to install it.

#### Option 2: Build and install with ADB

From the project directory, build the release APK and list connected devices:

```bash
flutter build apk --release
adb devices
```
Copy the serial for the target device from the `adb devices` output, then run:

```bash
adb -s YOUR_DEVICE_ID install -r build/app/outputs/apk/release/app-release.apk
```

Replace YOUR_DEVICE_ID with the serial shown by adb devices. The -s option selects that device, even if it’s the only one connected. The -r option installs the APK or replaces an existing installation while keeping its data. Updating an existing app requires the same release signing key.

Bump `version:` in `pubspec.yaml` (the number after `+`) for each release.

**Note:** Android is the only supported platform so far.
