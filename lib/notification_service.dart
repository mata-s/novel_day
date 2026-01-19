import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  /// グローバルナビゲーターキー（通知タップ時の画面遷移で使用）
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// アプリ起動時に1回だけ呼ぶ
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // タイムゾーン初期化
    await _configureLocalTimeZone();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOSInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iOSInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // 通知タップ時のpayload判定
        if (response.payload == 'today') {
          NotificationNavigation.toTodayPage();
        }
      },
    );

    // Android 13+ 通知許可リクエスト
    await requestPermissionIfNeeded();

    // 毎日21時のリマインダーをセット
    await scheduleDailyMemoReminder();
  }

  /// 設定画面などから呼べる通知許可リクエスト（Android 13+ / iOS）
  static Future<void> requestPermissionIfNeeded() async {
    // Android 13+ 通知許可
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    // iOS 通知許可
    final iosPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  /// OSの通知設定画面を開く（ユーザーがON/OFFを切り替える場所）
  static Future<void> openNotificationSettings() async {
    await AppSettings.openAppSettings(type: AppSettingsType.notification);
  }

  static Future<void> _requestAndroidNotificationPermission() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }
  }

  static Future<void> _configureLocalTimeZone() async {
    tz.initializeTimeZones();
    String timezone;
    try {
      timezone = await FlutterNativeTimezone.getLocalTimezone();
    } catch (e) {
      if (kDebugMode) {
        print('Timezone error: $e');
      }
      timezone = 'Asia/Tokyo'; // 念のためデフォルト
    }
    tz.setLocalLocation(tz.getLocation(timezone));
  }

  /// 毎日21:00に「メモしよう」通知を出す
  static Future<void> scheduleDailyMemoReminder() async {
    const int id = 0;

    // いったん同じIDの既存スケジュールをキャンセル
    await _plugin.cancel(id);

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      21, // 21:00
    );

    // すでに21時を過ぎていたら翌日に
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      '今日の出来事をメモしませんか？',
      '数行だけでもOK。今日の物語を残しておきましょう。',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_memo_channel',
          '毎日のメモリマインダー',
          channelDescription: 'NovelDayで毎日メモを促す通知',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: 'today',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.wallClockTime,
      matchDateTimeComponents: DateTimeComponents.time, // 毎日同じ時間に繰り返し
    );
  }
}

/// 通知タップ時の画面遷移ヘルパー
class NotificationNavigation {
  /// 通知から「今日のページ」へ遷移させる
  ///
  /// 現状はトップページ('/')に遷移しています。
  /// TodayPage に専用ルート名がある場合は、`'/'` を `'/today'` などに変更してください。
  static void toTodayPage() {
    final navigator = NotificationService.navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    navigator.pushNamedAndRemoveUntil(
      '/',
      (route) => false,
    );
  }
}
