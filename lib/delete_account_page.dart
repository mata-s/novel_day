import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';


class DeleteAccountConfirmPage extends StatefulWidget {
  const DeleteAccountConfirmPage({super.key});

  @override
  State<DeleteAccountConfirmPage> createState() => _DeleteAccountConfirmPageState();
}

class _DeleteAccountConfirmPageState extends State<DeleteAccountConfirmPage> {
  bool _loading = false;
  String? _error;

  bool _loadingCounts = true;
  int? _dailyCount;
  int? _weeklyCount;
  int? _monthlyCount;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _dailyCount = null;
          _weeklyCount = null;
          _monthlyCount = null;
          _loadingCounts = false;
        });
        return;
      }

      // NOTE: Adjust these strings if your `chapter_type` differs.
      const dailyType = 'daily';
      const weeklyType = 'weekly';
      const monthlyType = 'monthly';

      Future<int> countByType(String type) async {
        final res = await _supabase
            .from('entries')
            .select('id')
            .eq('user_id', user.id)
            .eq('chapter_type', type)
            .count(CountOption.exact);
        return res.count;
      }

      final results = await Future.wait<int>([
        countByType(dailyType),
        countByType(weeklyType),
        countByType(monthlyType),
      ]);

      if (!mounted) return;
      setState(() {
        _dailyCount = results[0];
        _weeklyCount = results[1];
        _monthlyCount = results[2];
        _loadingCounts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dailyCount = null;
        _weeklyCount = null;
        _monthlyCount = null;
        _loadingCounts = false;
      });
    }
  }

  Future<void> _deleteAccount() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('ログイン状態を確認できませんでした。いったんアプリを再起動してお試しください。');
      }

      // Call Supabase Edge Function (must be deployed on Supabase side).
      // This function should:
      // - authenticate the caller (JWT)
      // - delete the caller's data (entries/chapters/etc.)
      // - delete the auth user via admin API
      final res = await _supabase.functions.invoke(
        'delete-account',
        body: <String, dynamic>{},
      );

      // If the function returns non-2xx, supabase_flutter throws; but we keep a defensive check.
      if (res.status != 200 && res.status != 204) {
        throw Exception('削除に失敗しました（status=${res.status}）。しばらくしてから再度お試しください。');
      }

      // Sign out locally (session may already be invalid after deletion, so be defensive).
      try {
        await _supabase.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // ignore
      }

      if (!mounted) return;

      // Replace the whole stack so the UI surely shows logged-out state.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirmAndDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('最終確認'),
          content: const Text(
            'アカウント削除は取り消せません。\n'
            '本当に削除しますか？',
          ),
          actions: [
            TextButton(
              onPressed: _loading ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: _loading ? null : () => Navigator.of(ctx).pop(true),
              child: const Text('削除する'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      await _deleteAccount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget countChip(String label, int? value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor.withOpacity(0.6)),
          boxShadow: [
            BoxShadow(
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, 6),
              color: Colors.black.withOpacity(0.04),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              value == null ? '-' : '${value}件',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('アカウント削除')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Main card
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: theme.dividerColor.withOpacity(0.7)),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                            color: Colors.black.withOpacity(0.06),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                height: 44,
                                width: 44,
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.delete_outline, color: Colors.red),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'アカウントを削除します',
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'この操作は取り消せません',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurface.withOpacity(0.65),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '削除すると、保存されたデータ（記録・週のまとめ・月の短編）や設定情報が端末・サーバーから削除されます。',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 14),

                          // Counts
                          Text(
                            '削除対象のデータ件数',
                            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: _loadingCounts
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      countChip('記録', _dailyCount),
                                      countChip('週のまとめ', _weeklyCount),
                                      countChip('月の短編', _monthlyCount),
                                    ],
                                  ),
                          ),

                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.red.withOpacity(0.20)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline, color: Colors.red),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '削除が完了すると自動的にログアウトされます。',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.red.withOpacity(0.25)),
                              ),
                              child: Text(
                                _error!,
                                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    Text(
                      '※ 誤って削除しないよう、削除ボタンを押すと最終確認が表示されます。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('戻る'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _loading ? null : _confirmAndDelete,
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('削除する'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}