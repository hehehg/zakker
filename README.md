# ذكّرني (Zakker)
1. ارفع الملفات على مستودع GitHub جديد.
2. في Firebase: أنشئ مشروع > فعّل Authentication (Email/Password) > أنشئ Firestore.
3. أضف تطبيق ويب في Firebase وانسخ القيم داخل lib/firebase_options.dart.
4. قواعد Firestore:
   match /users/{uid}/{doc=**} { allow read, write: if request.auth.uid == uid; }
5. من تبويب Actions حمّل ملف APK وملف نسخة ويندوز.
