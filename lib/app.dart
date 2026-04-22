import 'package:flutter/material.dart';

import 'core/firebase/firebase_initializer.dart';
import 'features/call/presentation/pages/home_page.dart';

class WebRtcApp extends StatelessWidget {
  const WebRtcApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize Firebase before building the app
    return FutureBuilder<void>(
      future: FirebaseInitializer.ensureInitialized(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }

        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Firebase initialization failed.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Flutter WebRTC',
          theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
          home: const HomePage(),
        );
      },
    );
  }
}
