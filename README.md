# 🚗 CoRides - AI-Powered Ride Sharing Platform

[![Flutter](https://img.shields.io/badge/Flutter-3.10+-02569B?logo=flutter)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Enabled-FFCA28?logo=firebase)](https://firebase.google.com)
[![Gemini AI](https://img.shields.io/badge/Gemini-AI%20Powered-4285F4?logo=google)](https://ai.google.dev)
[![License](https://img.shields.io/badge/License-Public-brightgreen)]()

**CoRides** is a revolutionary ride-sharing application that leverages **Google Gemini AI** as an active orchestration agent. Unlike traditional ride-sharing apps, CoRides allows users to negotiate rides through natural voice and text conversations, with AI intelligently matching riders with drivers based on multi-stop route proximity and negotiated prices.

---

## ✨ Key Features

### 🤖 **AI-Powered Ride Negotiation**
- **Voice & Text Interface**: Interact with Gemini AI to book rides naturally
- **Smart Slot-Filling**: AI extracts origin, destination, time, and price from conversations
- **Intelligent Matching**: Multi-stop route optimization for drivers and riders
- **Live Voice Chat**: Real-time voice interaction with Gemini AI using native audio preview

### 🗺️ **Advanced Mapping**
- **Google Maps Integration**: Real-time location tracking and route visualization
- **Multi-Stop Routes**: Drivers can set waypoints for optimized passenger pickup
- **Proximity Matching**: 2km radius matching algorithm for efficient ride sharing
- **Live Route Polylines**: Visual representation of active rides

### 💬 **Communication**
- **AI Chat Interface**: Full-featured chat with Gemini AI using Flutter AI Toolkit
- **Message History**: Complete conversation logs for all interactions
- **Context Awareness**: AI remembers conversation context for seamless booking

### 💰 **Wallet & Payments**
- **Built-in Wallet System**: Track earnings and expenses
- **Ledger-Based Transactions**: Transparent payment records
- **Cash & Wallet Options**: Flexible payment methods

### 🔐 **Authentication**
- **Firebase Phone Auth**: Secure OTP-based authentication
- **User Profiles**: Separate rider and driver roles
- **Cloud Firestore**: Real-time data synchronization

---

## 🛠️ Technology Stack

| Category | Technology |
|----------|-----------|
| **Framework** | Flutter 3.10+ |
| **Backend** | Firebase (Auth, Firestore, Cloud Functions) |
| **AI Engine** | Google Gemini 2.5 Flash (with native audio preview) |
| **Maps** | Google Maps SDK, Places API, Geocoding |
| **Voice** | Speech-to-Text, Flutter TTS |
| **State Management** | Provider |
| **Languages** | Dart, Node.js/Python (Cloud Functions) |

---

## 📱 Supported Platforms

- ✅ **Android**
- ✅ **iOS**
- ✅ **Web** (PWA)
- ✅ **Windows**
- ✅ **macOS**
- ✅ **Linux**

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK 3.10 or higher
- Dart SDK
- Firebase CLI
- Google Cloud Platform account (for Gemini API)
- Android Studio / Xcode (for mobile development)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/faisal-ismail/corides.git
   cd corides
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**
   - Create a Firebase project at [Firebase Console](https://console.firebase.google.com)
   - Enable Phone Authentication
   - Enable Cloud Firestore
   - Download and add configuration files:
     - `google-services.json` (Android) → Place in `android/app/`
     - `GoogleService-Info.plist` (iOS) → Place in `ios/Runner/`
   - **Note:** These files are in `.gitignore` for security—do not commit them
   - Run FlutterFire CLI:
     ```bash
     flutterfire configure
     ```

4. **Set up Gemini API**
   - Get your API key from [Google AI Studio](https://makersuite.google.com/app/apikey)
   - Create `lib/constants.dart` with:
     ```dart
     class AppConstants {
       static const String geminiApiKey = 'YOUR_API_KEY_HERE';
       static const String googleMapsApiKey = 'YOUR_MAPS_API_KEY_HERE';
     }
     ```
   - **Note:** `lib/constants.dart` is in `.gitignore` for security—do not commit it

5. **Configure Google Maps**
   - Enable Maps SDK for Android/iOS in Google Cloud Console
   - Add API keys to:
     - `android/app/src/main/AndroidManifest.xml`
     - `ios/Runner/AppDelegate.swift`

6. **Run the app**
   ```bash
   flutter run
   ```

---

## 📂 Project Structure

```
lib/
├── main.dart                 # App entry point & home screen
├── constants.dart            # API keys and constants
├── firebase_options.dart     # Firebase configuration
├── models/                   # Data models
│   ├── ride.dart
│   ├── user.dart
│   ├── message.dart
│   └── payment.dart
├── screens/                  # UI screens
│   ├── gemini_chat_screen.dart
│   ├── gemini_live_voice_screen.dart
│   └── ...
├── services/                 # Business logic
│   ├── auth_service.dart
│   ├── gemini_service.dart
│   ├── firestore_service.dart
│   └── location_service.dart
├── widgets/                  # Reusable components
└── logic/                    # App logic
```

---

## 🔥 Firebase Collections

### `users`
```javascript
{
  uid: String,
  phone_number: String,
  role: 'rider' | 'driver',
  wallet_balance: Number,
  created_at: Timestamp
}
```

### `rides`
```javascript
{
  ride_id: String,
  creator_id: String,
  type: 'request' | 'offer',
  origin: { geopoint: GeoPoint, address: String },
  destination: { geopoint: GeoPoint, address: String },
  waypoints: [GeoPoint],
  departure_time: Timestamp,
  status: 'pending' | 'matched' | 'ongoing' | 'completed' | 'cancelled',
  negotiated_price: Number,
  seats_available: Number
}
```

### `messages`
```javascript
{
  message_id: String,
  user_id: String,
  timestamp: Timestamp,
  is_user_message: Boolean,
  content: String,
  intent_extracted: Object
}
```

### `payments`
```javascript
{
  transaction_id: String,
  ride_id: String,
  payer_id: String,
  payee_id: String,
  amount: Number,
  method: 'cash' | 'wallet',
  status: 'completed'
}
```

---

## 🎯 Core Features Implementation

### AI-Assisted Booking Flow

1. **User Interaction**: User taps the Gemini FAB button
2. **Voice/Text Input**: User speaks or types their ride request
3. **Slot Filling**: Gemini AI extracts:
   - Origin location
   - Destination location
   - Departure time
   - Price preference
4. **Validation**: AI asks follow-up questions for missing information
5. **Confirmation**: Once complete, ride request is created in Firestore
6. **Matching**: Cloud Functions match riders with nearby drivers

### Multi-Stop Route Matching

- Drivers set origin, destination, and waypoints
- Algorithm checks if rider's route is within 2km of driver's polyline
- Results sorted by price and proximity
- Real-time updates as drivers accept/decline

---

## 📦 Key Dependencies

```yaml
dependencies:
  flutter_sdk: flutter
  firebase_core: ^4.4.0
  firebase_auth: ^6.1.4
  cloud_firestore: ^6.1.2
  google_generative_ai: ^0.4.7
  google_maps_flutter: ^2.14.0
  geolocator: ^14.0.2
  geocoding: ^3.0.0
  flutter_ai_toolkit: ^1.0.0
  firebase_ai: ^3.7.0
  speech_to_text: ^7.3.0
  flutter_tts: ^4.2.5
  provider: ^6.1.5
  http: ^1.2.1
```

---

## 🎨 UI/UX Highlights

- **Material 3 Design**: Modern, clean interface
- **Interactive Map**: Full-screen Google Maps on home screen
- **Floating Action Button**: Quick access to AI assistant
- **Bottom Navigation**: Easy navigation between Home, Messages, and Wallet
- **Drawer Menu**: Access to profile, settings, and Gemini chat
- **Real-time Updates**: Live ride status and location tracking

---

## 🔒 Security & Privacy

- Phone number authentication via Firebase
- Secure API key management
- Firestore security rules for data protection
- Location permissions handled properly
- No real payment gateway (ledger system for MVP)

---

## 🧪 Testing

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage
```

---

## 🚧 Roadmap

- [ ] Real payment gateway integration
- [ ] Driver verification system
- [ ] Ride rating and reviews
- [ ] Push notifications
- [ ] In-app messaging between riders and drivers
- [ ] Advanced route optimization
- [ ] Carpooling for multiple riders

---

## 🤝 Contributing

This is a public open-source project. Contributions are welcome! Please feel free to submit pull requests and issues.

---



---

## 👨‍💻 Developer

Developed with ❤️ using Flutter and powered by Google Gemini AI

---

## 📞 Support

For issues and questions, please contact the development team.

---

## 🙏 Acknowledgments

- **Google Gemini AI** for advanced natural language processing
- **Firebase** for backend infrastructure
- **Flutter** for cross-platform development
- **Google Maps** for mapping services

---

**Powered by Gemini AI** 🚀
