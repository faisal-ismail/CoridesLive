# Security & Sensitive Files

This project contains sensitive configuration files that should **never** be committed to version control.

## Files to Configure Locally

### 1. **lib/constants.dart**
- **Purpose**: Contains API keys for Gemini and Google Maps
- **How to set up**:
  1. Copy `lib/constants.example.dart` to `lib/constants.dart`
  2. Fill in your actual API keys:
     - Gemini API Key: https://makersuite.google.com/app/apikey
     - Google Maps API Key: https://console.cloud.google.com
  3. **NEVER commit this file**

### 2. **android/app/google-services.json**
- **Purpose**: Firebase configuration for Android
- **How to set up**:
  1. Go to [Firebase Console](https://console.firebase.google.com)
  2. Create or select your project
  3. Add Android app and download `google-services.json`
  4. Place in `android/app/`
  5. **NEVER commit this file**

### 3. **ios/Runner/GoogleService-Info.plist**
- **Purpose**: Firebase configuration for iOS
- **How to set up**:
  1. Go to [Firebase Console](https://console.firebase.google.com)
  2. Create or select your project
  3. Add iOS app and download `GoogleService-Info.plist`
  4. Place in `ios/Runner/`
  5. **NEVER commit this file**

## Environment Variables

For additional security, consider using environment variables:

```bash
export GEMINI_API_KEY="your-key-here"
export GOOGLE_MAPS_API_KEY="your-key-here"
```

Then load them in your constants file:

```dart
class AppConstants {
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
}
```

## Security Best Practices

✅ **DO:**
- Store sensitive keys in environment variables or secure vaults
- Use `.gitignore` to prevent accidental commits
- Rotate API keys regularly
- Use Firebase security rules to restrict data access
- Enable API restrictions in Google Cloud Console

❌ **DON'T:**
- Commit API keys to version control
- Share configuration files with sensitive data
- Use the same keys across environments (dev, staging, production)
- Expose API keys in client-side code (use backend for sensitive operations)

## Setup for New Developers

1. Clone the repository
2. Create local configuration files following the guides above
3. Ask the team lead for the configuration templates if needed
4. Never commit these files
