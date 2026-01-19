import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import 'splash_page.dart';
import 'home.dart';
import 'services.dart';
import 'today_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔽 AdMob 初期化（google_mobile_ads）
  await MobileAds.instance.initialize();

  await Supabase.initialize(
    url: 'https://gycyfdggohvtadgywniw.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd5Y3lmZGdnb2h2dGFkZ3l3bml3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUxNzk0MDMsImV4cCI6MjA4MDc1NTQwM30.FqO7dCtXtwL0C50rbTf3jLOJTF6DuxqKkL1E3qvaMVI',
  );

  // 🔽 追加：RevenueCat 初期化
  await PremiumManager.init();
  
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NovelDay',
      theme: ThemeData(useMaterial3: true),

      // ✅ 通知タップから遷移できるようにする
      navigatorKey: NotificationService.navigatorKey,

      // ✅ 通知タップで開きたいページ
      routes: {
        '/today': (_) => const TodayPage(),
      },

      home: const SplashPage(),
    );
  }
}

class SignedInRouter extends StatefulWidget {
  const SignedInRouter({super.key, required this.session});

  final Session session;

  @override
  State<SignedInRouter> createState() => _SignedInRouterState();
}

class _SignedInRouterState extends State<SignedInRouter> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    final client = Supabase.instance.client;
    final userId = widget.session.user.id;

    try {
      await client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const HomeScreen();
  }
}