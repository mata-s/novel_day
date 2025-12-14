import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';
import 'sign_up_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.signedInBuilder,
  });

  final Widget Function(BuildContext context, Session session) signedInBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _prefsLoaded = false;
  bool _hasRegistered = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final flag = prefs.getBool('has_registered') ?? false;
    if (!mounted) return;
    setState(() {
      _hasRegistered = flag;
      _prefsLoaded = true;
    });
  }

  Future<void> _markRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_registered', true);
    if (!mounted) return;
    setState(() => _hasRegistered = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session =
            snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;

        if (session == null) {
          // 未ログイン：初回は SignUp、2回目以降は Login
          return _hasRegistered
              ? const LoginScreen()
              : SignUpScreen(onRegistered: _markRegistered);
        }

        // ログイン済み：フラグも立てる（匿名開始でもOK）
        _markRegistered();
        return widget.signedInBuilder(context, session);
      },
    );
  }
}