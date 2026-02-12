import 'package:flutter/material.dart';
import 'package:novel_day/services.dart';
import 'package:novel_day/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:novel_day/transfer_page.dart';
import 'package:novel_day/edit_profile_page.dart';
import 'package:novel_day/transfer_login_page.dart';
import 'package:novel_day/delete_account_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autoWeeklyNovel = false;
  bool _autoMonthlyNovel = false;
  bool _loadingAutoNovelSettings = true;

  @override
  void initState() {
    super.initState();
    _loadAutoNovelSettings();
  }

Future<void> _loadAutoNovelSettings() async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) {
    setState(() {
      _loadingAutoNovelSettings = false;
    });
    return;
  }

  try {
    final res = await Supabase.instance.client
        .from('profiles')
        .select('auto_weekly_novel, auto_monthly_novel')
        .eq('id', user.id)
        .maybeSingle();

    setState(() {
      _autoWeeklyNovel = (res?['auto_weekly_novel'] as bool?) ?? false;
      _autoMonthlyNovel = (res?['auto_monthly_novel'] as bool?) ?? false;
      _loadingAutoNovelSettings = false;
    });
  } catch (e) {
    debugPrint('自動生成フラグの読み込みに失敗: $e');
    setState(() {
      _autoWeeklyNovel = false;
      _autoMonthlyNovel = false;
      _loadingAutoNovelSettings = false;
    });
  }
}

Future<void> _updateAutoNovelSettings({
  bool? weekly,
  bool? monthly,
}) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) {
    debugPrint('updateAutoNovelSettings: user is null');
    return;
  }

  final newWeekly = weekly ?? _autoWeeklyNovel;
  final newMonthly = monthly ?? _autoMonthlyNovel;

  debugPrint('updateAutoNovelSettings called. '
      'userId=${user.id}, weekly=$newWeekly, monthly=$newMonthly');

  // まずローカルの状態を更新（UI 反映）
  setState(() {
    _autoWeeklyNovel = newWeekly;
    _autoMonthlyNovel = newMonthly;
  });

  try {
    final client = Supabase.instance.client;

    // profiles テーブルを更新
    final res = await client
        .from('profiles')
        .update({
          'auto_weekly_novel': newWeekly,
          'auto_monthly_novel': newMonthly,
        })
        .eq('id', user.id);

    debugPrint('profiles update result: $res');

    // auth.user_metadata にも保存したい場合（オマケ）
    await client.auth.updateUser(
      UserAttributes(
        data: {
          'auto_weekly_novel': newWeekly,
          'auto_monthly_novel': newMonthly,
        },
      ),
    );

    debugPrint('updateUser metadata done.');
  } catch (e, st) {
    debugPrint('自動生成フラグの更新に失敗: $e');
    debugPrint(st.toString());

    // 失敗したのでローカルの値も元に戻す
    setState(() {
      _autoWeeklyNovel = !_autoWeeklyNovel;
      _autoMonthlyNovel = !_autoMonthlyNovel;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('自動生成設定の保存に失敗しました')),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final isAnonymous =
        user != null && (user.email == null || user.email!.isEmpty);
    // cacheプレミアム状態
    final isPremium = PremiumManager.isPremium.value;

    // 特別テスト用プレミアムユーザー（RevenueCat未課金でもプレミアム扱いにする）
    const testPremiumUserId = '9491e148-1a07-4c6f-ad7a-39cdb3b74b0c';
    final isTestPremiumUser = user?.id == testPremiumUserId;

    // 実質プレミアム判定（通常のプレミアム or テスト用ユーザー）
    final effectivePremium = isPremium || isTestPremiumUser;

    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _Header(
            title: '設定',
            subtitle: 'アカウント・プレミアム・その他',
          ),
          const SizedBox(height: 16),

          // ===== アカウント =====
          const _SectionTitle('アカウント'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              _ModernTile(
                leading: _IconBubble(
                  icon: Icons.person_outline,
                  background: cs.primaryContainer,
                  foreground: cs.onPrimaryContainer,
                ),
                title: 'プロフィール',
                subtitle: 'プロフィールを変更',
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EditProfilePage()),
                  );
                },
              ),
              const _Divider(),
              _ModernTile(
                leading: _IconBubble(
                  icon: Icons.sync_alt_rounded,
                  background: cs.secondaryContainer,
                  foreground: cs.onSecondaryContainer,
                ),
                title: 'データを引き継ぐ',
                subtitle: isAnonymous
                    ? 'メールアドレスを設定して、端末変更に備えましょう'
                    : '引き継ぎ設定は完了しています',
                trailing: isAnonymous
                    ? const Icon(Icons.chevron_right)
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          Chip(
                            label: const Text('設定済み'),
                            labelStyle: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w700,
                            ),
                            backgroundColor: Colors.green.shade50,
                            side: BorderSide(color: Colors.green.shade200),
                          ),
                        ],
                      ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TransferPage()),
                  );
                },
              ),
              const _Divider(),
              _ModernTile(
                leading: _IconBubble(
                  icon: Icons.login_rounded,
                  background: cs.secondaryContainer,
                  foreground: cs.onSecondaryContainer,
                ),
                title: '引き継ぎでログイン',
                subtitle: '設定済みのメールアドレスでログイン',
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TransferLoginPage()),
                  );
                },
              ),
              const _Divider(),
              _ModernTile(
                leading: _IconBubble(
                  icon: Icons.auto_stories_outlined,
                  background: cs.surfaceContainerHighest,
                  foreground: cs.onSurface,
                ),
                title: '週の小説を自動生成',
                subtitle: 'サブスクユーザー向けに週ごとの小説を自動で作成（毎週月曜 深夜1時ごろ）',
                trailing: _loadingAutoNovelSettings
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Switch(
                        value: _autoWeeklyNovel,
                        onChanged: effectivePremium
                            ? (value) {
                                _updateAutoNovelSettings(weekly: value);
                              }
                            : null, // 非課金ならグレーアウト
                      ),
                onTap: effectivePremium
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PremiumPage(),
                          ),
                        );
                      },
              ),
              const _Divider(),
              _ModernTile(
                leading: _IconBubble(
                  icon: Icons.menu_book_outlined,
                  background: cs.surfaceContainerHighest,
                  foreground: cs.onSurface,
                ),
                title: '月の小説を自動生成',
                subtitle: 'サブスクユーザー向けに月ごとの小説を自動で作成（毎月1日 深夜3時ごろ）',
                trailing: _loadingAutoNovelSettings
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Switch(
                        value: _autoMonthlyNovel,
                        onChanged: effectivePremium
                            ? (value) {
                                _updateAutoNovelSettings(monthly: value);
                              }
                            : null, // 非課金ならグレーアウト
                      ),
                onTap: effectivePremium
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PremiumPage(),
                          ),
                        );
                      },
              ),
              const _Divider(),
              _ModernTile(
                leading: _IconBubble(
                  icon: Icons.logout,
                  background: cs.surfaceContainerHighest,
                  foreground: cs.onSurface,
                ),
                title: 'ログアウト',
                subtitle: 'この端末からログアウトします',
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const TransferLoginPage()),
                    (route) => false,
                  );
                },
              ),
              const _Divider(),
              _ModernTile(
                leading: _IconBubble(
                  icon: Icons.delete_outline,
                  background: Colors.red.shade50,
                  foreground: Colors.red,
                ),
                title: 'アカウント削除',
                subtitle: 'この操作は取り消せません',
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DeleteAccountConfirmPage(),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 22),

          // ===== プレミアム =====
          const _SectionTitle('プレミアム'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              _ModernTile(
                leading: _IconBubble(
                  icon: Icons.workspace_premium_outlined,
                  background: cs.tertiaryContainer,
                  foreground: cs.onTertiaryContainer,
                ),
                title: 'プレミアム機能',
                subtitle: 'もっと書くのが楽しくなる機能',
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PremiumPage()),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 22),

          // ===== 通知 =====
          const _SectionTitle('通知'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              _ModernTile(
                leading: _IconBubble(
                  icon: Icons.notifications_active_outlined,
                  background: cs.surfaceContainerHighest,
                  foreground: cs.onSurface,
                ),
                title: '毎日のリマインド',
                subtitle: '毎日21時に通知を受け取る',
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  NotificationService.openNotificationSettings();
                },
              ),
              const _Divider(),
            ],
          ),

          const SizedBox(height: 22),

          // ===== その他 =====
          const _SectionTitle('その他'),
          const SizedBox(height: 10),
          _SettingsCard(
            children: [
              _ModernTile(
                leading: _IconBubble(
                  icon: Icons.description_outlined,
                  background: cs.surfaceContainerHighest,
                  foreground: cs.onSurface,
                ),
                title: '利用規約',
                subtitle: 'サービスの利用条件',
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final url = Uri.parse('https://novel-day-privacy.vercel.app/terms.html');
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                },
              ),
              const _Divider(),
              _ModernTile(
                leading: _IconBubble(
                  icon: Icons.privacy_tip_outlined,
                  background: cs.surfaceContainerHighest,
                  foreground: cs.onSurface,
                ),
                title: 'プライバシーポリシー',
                subtitle: '個人情報の取り扱い',
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final url = Uri.parse('https://novel-day-privacy.vercel.app/index.html');
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                },
              ),
              const _Divider(),
              _ModernTile(
                leading: _IconBubble(
                  icon: Icons.mail_outline,
                  background: cs.surfaceContainerHighest,
                  foreground: cs.onSurface,
                ),
                title: 'お問い合わせ',
                subtitle: 'ご意見・ご質問・削除依頼',
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final url = Uri.parse('https://novel-day-privacy.vercel.app/contact.html');
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                },
              ),
            ],
          ),

          const SizedBox(height: 26),

          // ===== フッター =====
          Text(
            'Version 1.3.0',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;

  const _Header({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.black54),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withOpacity(0.5),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _ModernTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _ModernTile({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: leading,
      title: Text(
        title,
        style:
            Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.black54),
            ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;

  const _IconBubble({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: foreground),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 14, endIndent: 14);
  }
}
