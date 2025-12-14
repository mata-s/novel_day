import 'package:flutter/material.dart';
import 'package:novel_day/policy_page.dart';
import 'package:novel_day/services.dart';
import 'package:novel_day/terms_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:novel_day/transfer_page.dart';
import 'package:novel_day/edit_profile_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final isAnonymous =
        user != null && (user.email == null || user.email!.isEmpty);

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
                title: '名前・一人称',
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
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TermsPage()),
                  );
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
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyPage(),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 26),

          // ===== フッター =====
          Text(
            'Version 1.0.0',
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

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}