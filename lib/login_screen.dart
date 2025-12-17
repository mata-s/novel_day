import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sign_up_screen.dart';
import 'home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _error;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _friendlyAuthError(Object e) {
    // Supabase Auth の代表的なエラーを日本語に変換
    final msg = e.toString();

    // 無効な資格情報（メール or パスワード違い）
    if (msg.contains('Invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'メールアドレスまたはパスワードが間違っています。';
    }

    // メール未確認
    if (msg.contains('Email not confirmed') || msg.contains('email_not_confirmed')) {
      return 'メールアドレスの確認が完了していません。受信メールのリンクを確認してください。';
    }

    // レート制限など
    if (msg.contains('rate limit') || msg.contains('too_many_requests')) {
      return '試行回数が多すぎます。しばらく待ってからお試しください。';
    }

    // ネットワーク系
    if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
      return '通信に失敗しました。ネットワーク状況を確認してください。';
    }

    return 'ログインに失敗しました。入力内容を確認してもう一度お試しください。';
  }

  Future<void> _signInWithEmail() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      if (email.isEmpty || password.isEmpty) {
        throw Exception('メールアドレスとパスワードを入力してください');
      }

      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      // 遷移しない：AuthGate が auth 状態変化で自動切替
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログインしました')),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyAuthError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyAuthError(e));
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('ログイン')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ログインしてデータを引き継ぎます。\n\n以前にメール登録した方は、メールアドレスとパスワードでログインしてください。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'メールアドレス',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'パスワード',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _loading ? null : _signInWithEmail,
              child: const Text('ログイン'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loading
                  ? null
                  : () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const SignUpScreen()),
                      );
                    },
              child: Text(
                'はじめての方はこちら（初回画面へ）',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}