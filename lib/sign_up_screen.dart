import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, this.onRegistered});

  final Future<void> Function()? onRegistered;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  bool _loading = false;
  String? _error;

  final _nameController = TextEditingController();
  final _firstPersonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onInputsChanged);
    _firstPersonController.addListener(_onInputsChanged);
  }

  void _onInputsChanged() {
    if (!mounted) return;
    // プレビュー更新
    setState(() {});
  }

  @override
  void dispose() {
    _nameController.removeListener(_onInputsChanged);
    _firstPersonController.removeListener(_onInputsChanged);
    _nameController.dispose();
    _firstPersonController.dispose();
    super.dispose();
  }

  Future<void> _startWithoutRegistration() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      final res = await client.auth.signInAnonymously();
      final user = res.user;
      if (user == null) throw Exception('ユーザー作成に失敗しました');

      final name = _nameController.text.trim();
      final firstPerson = _firstPersonController.text.trim();
      if (name.isEmpty) throw Exception('名前を入力してください');

      await client.from('profiles').insert({
        'id': user.id,
        'name': name,
        'first_person': firstPerson.isEmpty ? 'わたし' : firstPerson,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_registered', true);

      await widget.onRegistered?.call();
      // 遷移しない：AuthGate が auth 状態変化で自動切替
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '開始に失敗しました: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('はじめる')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
            const SizedBox(height: 8),
            Center(
              child: Column(
                children: [
                  Icon(Icons.auto_stories_outlined, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    'NovelDay',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '今日の一言が、物語になる。',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'まずは「名前」と「一人称」を教えてだくさい。\n物語の語り口に反映されます。',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'プレビュー',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '例：\n「${_firstPersonController.text.trim().isEmpty ? 'わたし' : _firstPersonController.text.trim()}は、今日の出来事を胸にしまった。\n…そして${_nameController.text.trim().isEmpty ? 'あなた' : _nameController.text.trim()}の物語が始まる。」',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '※ 入力するとプレビューが変わります',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '名前（表示名）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _firstPersonController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '一人称',
                hintText: '例：わたし / ぼく / 俺（空欄なら「わたし」）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _startWithoutRegistration,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('はじめる'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _loading
                  ? null
                  : () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
              child: const Text('データを引き継ぐ（ログイン）'),
            ),
                  ],
                ),
              ),
              ),
            );
          },
        ),
      ),
    );
  }
}