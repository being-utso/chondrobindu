// File generated or configured for Firebase options.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// [DefaultFirebaseOptions] provides the default FirebaseOptions for the current platform.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCfhrTv3AF6fVv1bL3iqzfJCmuyPGnRsGc',
    appId: '1:168312495417:web:5b2f2f53c8a4592a02dce8',
    messagingSenderId: '168312495417',
    projectId: 'chondrobindu',
    authDomain: 'chondrobindu.firebaseapp.com',
    storageBucket: 'chondrobindu.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC_WxVlANxBvjc79FC6L_L2fhpvMTdJKJU',
    appId: '1:168312495417:android:dd2b3ae44b56a12802dce8',
    messagingSenderId: '168312495417',
    projectId: 'chondrobindu',
    storageBucket: 'chondrobindu.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyChondrobinduIOSKeyPlaceholder',
    appId: '1:100000000000:ios:abcdef1234567890',
    messagingSenderId: '100000000000',
    projectId: 'chondrobindu-app',
    storageBucket: 'chondrobindu-app.appspot.com',
    iosBundleId: 'com.chondrobindu.app',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyChondrobinduMacOSKeyPlaceholder',
    appId: '1:100000000000:ios:abcdef1234567890',
    messagingSenderId: '100000000000',
    projectId: 'chondrobindu-app',
    storageBucket: 'chondrobindu-app.appspot.com',
    iosBundleId: 'com.chondrobindu.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyChondrobinduWindowsKeyPlaceholder',
    appId: '1:100000000000:web:abcdef1234567890',
    messagingSenderId: '100000000000',
    projectId: 'chondrobindu-app',
    authDomain: 'chondrobindu-app.firebaseapp.com',
    storageBucket: 'chondrobindu-app.appspot.com',
  );
}
