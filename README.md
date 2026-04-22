# Flutter WebRTC Video Caller

Clean Flutter implementation of a 1:1 video calling app using:

- `flutter_webrtc` for media + peer connection
- `cloud_firestore` for signaling (offer/answer/ICE)
- `firebase_core` for Firebase initialization

## Project Structure

```text
lib/
  app.dart
  core/
    firebase/
      firebase_initializer.dart
      firebase_options.dart
  features/
    call/
      data/
        signaling_repository.dart
      domain/
        models/
          call_role.dart
          ice_candidate_model.dart
          session_description_model.dart
      presentation/
        controllers/
          call_controller.dart
        pages/
          home_page.dart
        widgets/
          video_view.dart
  main.dart
```

## Use Your Existing Firebase Project

1. Install FlutterFire CLI (if not installed):
   - `dart pub global activate flutterfire_cli`
2. Configure this app to your existing Firebase project:
   - `flutterfire configure --project=<YOUR_EXISTING_PROJECT_ID>`
3. This command generates correct platform options in `firebase_options.dart`.

## Firestore Rules (for development)

Use temporary open rules while testing, then tighten before production:

```text
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /rooms/{roomId} {
      allow read, write: if true;
      match /{document=**} {
        allow read, write: if true;
      }
    }
  }
}
```

## Run

1. `flutter pub get`
2. `flutter run`

## Notes

- Caller taps **Create Room** and shares Room ID.
- Callee pastes Room ID and taps **Join Room**.
- **Hang Up** clears signaling data for that room.
