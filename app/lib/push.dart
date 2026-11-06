import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'common.dart';

// Firebase 콘솔 > 프로젝트 설정 > 내 앱(Android) 값. 빌드 시 --dart-define 으로 주입.
const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _appId = String.fromEnvironment('FIREBASE_APP_ID');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

/// FCM 푸시. Firebase 값이 주입되지 않은 빌드에서는 비활성화되고 앱 내 알림함만 동작한다.
class Push {
  static bool _ready = false;

  static Future<void> init() async {
    if (_apiKey.isEmpty || _appId.isEmpty) {
      debugPrint('푸시 비활성화: FIREBASE_* 값 없음');
      return;
    }
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          messagingSenderId: _senderId,
          projectId: _projectId,
        ),
      );
      await FirebaseMessaging.instance.requestPermission(); // Android 13+ 알림 권한
      FirebaseMessaging.instance.onTokenRefresh.listen(_save);
      _ready = true;
    } catch (e) {
      debugPrint('푸시 비활성화: $e');
    }
  }

  /// 로그인한 사용자의 기기 토큰을 profiles.fcm_token 에 저장
  static Future<void> registerToken() async {
    if (!_ready) return;
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null) await _save(t);
    } catch (e) {
      debugPrint('FCM 토큰 저장 실패: $e');
    }
  }

  static Future<void> _save(String token) async {
    if (db.auth.currentUser == null) return;
    await db.from('profiles').update({'fcm_token': token}).eq('id', uid);
  }
}
