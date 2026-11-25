import 'package:firebase_core/firebase_core.dart';
// املأ القيم من Firebase Console (إعدادات المشروع > تطبيق ويب)، أو شغّل: flutterfire configure
class DefaultFirebaseOptions {
  static const currentPlatform = FirebaseOptions(
    apiKey: 'PUT_API_KEY',
    appId: 'PUT_APP_ID',
    messagingSenderId: 'PUT_SENDER_ID',
    projectId: 'PUT_PROJECT_ID',
  );
}
