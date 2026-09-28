# Masstamilan Mobile App (Flutter)

This is the complete source code for your Masstamilan Mobile App! It uses an "Invisible Browser" (`HeadlessInAppWebView`) to cleanly bypass Cloudflare bot protection right from your phone.

## How to turn this into an Android App (.apk)

Since you do not currently have Flutter installed on your Windows computer, you need to install it to compile this code into a real app.

### Step 1: Install Flutter
1. Go to the [Official Flutter Windows Install Guide](https://docs.flutter.dev/get-started/install/windows).
2. Download the Flutter SDK and extract it.
3. Add the `flutter\bin` folder to your Windows PATH environment variable.
4. Install **Android Studio** (this provides the tools to build `.apk` files).

### Step 2: Build the App
Once Flutter is installed, open PowerShell or Command Prompt, and run these commands:

```powershell
# 1. Go to this folder
cd C:\Users\Naveen\.gemini\antigravity\scratch\MasstamilanMobileApp

# 2. Get all the plugins (WebView, CSV parser, File Picker, etc.)
flutter pub get

# 3. Build the Android APK!
flutter build apk
```

### Step 3: Install on your Phone
After it finishes building, you will find your shiny new app file located here:
`build\app\outputs\flutter-apk\app-release.apk`

Transfer that `.apk` file to your Android phone (via USB, Google Drive, or email), open it, and install it!
