import 'package:supabase_flutter/supabase_flutter.dart';
import 'home.dart';
import 'first_setup_page.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://gycyfdggohvtadgywniw.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd5Y3lmZGdnb2h2dGFkZ3l3bml3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUxNzk0MDMsImV4cCI6MjA4MDc1NTQwM30.FqO7dCtXtwL0C50rbTf3jLOJTF6DuxqKkL1E3qvaMVI',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checkingSession = true;
  bool _isLoggedIn = false;
  bool _hasProfile = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;

    if (session == null) {
      setState(() {
        _isLoggedIn = false;
        _hasProfile = false;
        _checkingSession = false;
      });
      return;
    }

    final user = session.user;

    try {
      final response = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final hasProfile = response != null;

      setState(() {
        _isLoggedIn = true;
        _hasProfile = hasProfile;
        _checkingSession = false;
      });
    } catch (e) {
      // プロフィール取得に失敗した場合は、とりあえずログイン済み扱い＆プロフィールありとしてホームに進ませる
      setState(() {
        _isLoggedIn = true;
        _hasProfile = true;
        _checkingSession = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // ログインしていない場合はログイン画面へ
    if (!_isLoggedIn) {
      return const LoginScreen();
    }

    // ログイン済み ＋ プロフィール未設定 → 初回設定画面へ
    if (!_hasProfile) {
      return const FirstSetupPage();
    }

    // ログイン済み ＋ プロフィールあり → ホーム画面へ
    return const HomeScreen();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signInAnonymously() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signInAnonymously();

      if (!mounted) return;

      // 匿名ログインに成功したら、再度 AuthGate を経由して
      // プロフィール有無によって FirstSetupPage / HomeScreen を出し分ける
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const AuthGate(),
        ),
      );
    } catch (e) {
      setState(() {
        _error = 'ログインに失敗しました: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NovelDay'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '一言メモから物語をつくるアプリ「NovelDay」へようこそ。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _signInAnonymously,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text('匿名ではじめる'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
