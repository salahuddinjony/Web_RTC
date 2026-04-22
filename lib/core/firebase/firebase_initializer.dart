import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';

class FirebaseInitializer {
  FirebaseInitializer._();

  static Future<void> ensureInitialized() async {
    // Check if Firebase is already initialized
    if (Firebase.apps.isNotEmpty) {
      return;
    }

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}
