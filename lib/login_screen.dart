import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sign_up_screen.dart';

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
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'ログインに失敗しました: $e');
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