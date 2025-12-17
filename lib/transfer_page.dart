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
  final _currentPass = TextEditingController();

  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _editing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email;
    if (email != null && email.isNotEmpty) {
      _email.text = email;
      _editing = false;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    _currentPass.dispose();
    super.dispose();
  }

  bool get _looksAnonymous {
    final user = Supabase.instance.client.auth.currentUser;
    // Supabase匿名だと email が null のことが多い（最も安定）
    return user != null && (user.email == null || user.email!.isEmpty);
  }

  Future<void> _saveCredentials() async {
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
      final currentPass = _currentPass.text;

      if (email.isEmpty) throw Exception('メールアドレスを入力してください');

      final isAnonymous = _looksAnonymous;
      final wantsPasswordChange = pass.isNotEmpty || pass2.isNotEmpty;

      if (wantsPasswordChange) {
        if (pass.length < 8) throw Exception('パスワードは8文字以上にしてください');
        if (pass != pass2) throw Exception('パスワード（確認）が一致しません');

        // 既存ユーザーがパスワード変更する場合のみ、現在のパスワードを必須にする
        if (!isAnonymous && currentPass.isEmpty) {
          throw Exception('現在のパスワードを入力してください');
        }
      }

      if (isAnonymous) {
        // 匿名→メール/パス登録（アカウントを“昇格”）
        await client.auth.updateUser(
          UserAttributes(
            email: email,
            password: pass,
          ),
        );
      } else {
        // 既存ユーザーの更新（メール・パスワード）
        // パスワード変更時は再認証（current password）が必要
        if (wantsPasswordChange) {
          final currentEmail = user.email;
          if (currentEmail == null || currentEmail.isEmpty) {
            throw Exception('現在のメールアドレスが取得できません');
          }

          // 再認証（現在のパスワードでサインイン）
          await client.auth.signInWithPassword(
            email: currentEmail,
            password: currentPass,
          );
        }

        await client.auth.updateUser(
          UserAttributes(
            email: email,
            password: wantsPasswordChange ? pass : null,
          ),
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wantsPasswordChange
                ? 'メール/パスワードを更新しました'
                : 'メールアドレスを更新しました',
          ),
        ),
      );

      // 変更画面を閉じる（登録済みユーザー向け）
      if (!isAnonymous) {
        setState(() => _editing = false);
      }
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
                    : '引き継ぎ設定済みです。必要なら「変更する」から更新できます。',
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
                      icon:
                          Icon(_obscurePass ? Icons.visibility : Icons.visibility_off),
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
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility
                          : Icons.visibility_off),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _saveCredentials,
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
                // 現在の設定（概要）
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.18),
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
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() {
                                  _editing = true;
                                  // 編集開始時にパス入力はクリア
                                  _currentPass.clear();
                                  _pass.clear();
                                  _pass2.clear();
                                });
                              },
                        child: const Text('変更する'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'このメールアドレスで、別の端末からログインできます。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),

                if (_editing) ...[
                  const SizedBox(height: 18),
                  Text(
                    '引き継ぎ設定を変更',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

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
                    controller: _currentPass,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '現在のパスワード（パス変更する場合のみ）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: _obscurePass,
                    decoration: InputDecoration(
                      labelText: '新しいパスワード（変更しないなら空でOK）',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                        icon: Icon(_obscurePass
                            ? Icons.visibility
                            : Icons.visibility_off),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass2,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      labelText: '新しいパスワード（確認）',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                        icon: Icon(_obscureConfirm
                            ? Icons.visibility
                            : Icons.visibility_off),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  setState(() => _editing = false);
                                  _currentPass.clear();
                                  _pass.clear();
                                  _pass2.clear();
                                },
                          child: const Text('キャンセル'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _loading ? null : _saveCredentials,
                          child: _loading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('更新する'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '※ メール変更後、設定によっては確認メールが届く場合があります。',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ]
            ],
          ),
        ),
      ),
    );
  }
}