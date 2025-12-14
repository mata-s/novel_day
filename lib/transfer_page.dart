import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransferPage extends StatefulWidget {
  const TransferPage({super.key});

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();

  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  bool get _looksAnonymous {
    final user = Supabase.instance.client.auth.currentUser;
    // Supabase匿名だと email が null のことが多い（最も安定）
    return user != null && (user.email == null || user.email!.isEmpty);
  }

  Future<void> _setEmailPassword() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw Exception('ログイン情報が見つかりません');

      final email = _email.text.trim();
      final pass = _pass.text;
      final pass2 = _pass2.text;

      if (email.isEmpty) throw Exception('メールアドレスを入力してください');
      if (pass.length < 8) throw Exception('パスワードは8文字以上にしてください');
      if (pass != pass2) throw Exception('パスワード（確認）が一致しません');

      // 匿名→メール/パス登録（アカウントを“昇格”）
      await client.auth.updateUser(
        UserAttributes(
          email: email,
          password: pass,
        ),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('引き継ぎ設定を保存しました')),
      );

      // メール確認がONのプロジェクトだと、確認メールが飛ぶことがある
      // その場合は「確認後にログインしてください」と出すと親切
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('引き継ぎ設定 完了'),
          content: const Text(
            'メール確認が有効な場合、確認メールが届くことがあります。\n'
            'メール内リンクの確認後、同じメール/パスでログインできます。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '失敗しました: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('データ引き継ぎ')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _looksAnonymous
                    ? 'この端末のデータを、メール/パスワードで引き継げるようにします。'
                    : 'すでにメール設定済みのアカウントです。',
              ),
              const SizedBox(height: 10),
              Text(
                'ユーザーID: ${user?.id ?? "-"}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (_looksAnonymous) ...[
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: _obscurePass,
                  decoration: InputDecoration(
                    labelText: 'パスワード（8文字以上）',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                      icon: Icon(_obscurePass ? Icons.visibility : Icons.visibility_off),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass2,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'パスワード（確認）',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      icon: Icon(_obscureConfirm ? Icons.visibility : Icons.visibility_off),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _setEmailPassword,
                    child: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('引き継ぎ設定を保存'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '※ 設定後は、別端末で同じメール/パスワードでログインできます。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ] else ...[
                Text(
                  '引き継ぎ設定済み',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // メールアドレスを目立たせて表示
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          Theme.of(context).colorScheme.primary.withOpacity(0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.email_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          user?.email ?? '-',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),
                const Text(
                  'このメールアドレスで、別の端末からログインできます。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],

              
            ],
          ),
        ),
      ),
    );
  }
}