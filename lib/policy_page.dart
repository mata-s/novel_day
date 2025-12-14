import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const String _effectiveDate = '2025-12-15'; // 必要に応じて変更

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('プライバシーポリシー'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const _Section(
              title: 'プライバシーポリシー（NovelDay）',
              children: [
                _P(
                  '本プライバシーポリシー（以下「本ポリシー」といいます。）は、NovelDay（以下「本サービス」といいます。）におけるユーザー情報の取扱いを定めるものです。',
                ),
              ],
            ),
            const _Divider(),

            const _Section(
              title: '1. 取得する情報',
              children: [
                _Li('アカウント情報（匿名ID、メールアドレス（設定した場合）など）'),
                _Li('プロフィール情報（表示名、一人称などユーザーが入力した情報）'),
                _Li('投稿データ（メモ、生成された文章、作成日時等）'),
                _Li('端末・利用情報（アプリの動作に必要な範囲の端末情報、ログ等）'),
                _Li('購入・課金情報（プレミアムの購入状態、取引識別子等）※カード情報は運営者が取得しません'),
                _Li('広告識別子等（広告配信を行う場合）'),
              ],
            ),
            const _Divider(),

            const _Section(
              title: '2. 利用目的',
              children: [
                _Li('本サービスの提供、本人確認（引き継ぎ設定を含む）、認証のため'),
                _Li('投稿データの保存、表示、同期のため'),
                _Li('プレミアム機能の提供、購入状態の確認、購入復元のため'),
                _Li('不正利用の防止、セキュリティ確保のため'),
                _Li('お問い合わせ対応、重要なお知らせの通知のため'),
                _Li('品質改善（クラッシュ・不具合解析等）のため'),
                _Li('広告の表示および効果測定（実施する場合）のため'),
              ],
            ),
            const _Divider(),

            const _Section(
              title: '3. 外部サービスの利用',
              children: [
                _P(
                  '本サービスは、機能提供のために以下の外部サービスを利用する場合があります。外部サービスの提供者が取得する情報の範囲や取扱いは、各社のプライバシーポリシーをご確認ください。',
                ),
                _Li('Supabase（認証・データベース）'),
                _Li('RevenueCat（サブスクリプション管理）'),
                _Li('Google AdMob（広告配信）※広告を表示する場合'),
              ],
            ),
            const _Divider(),

            const _Section(
              title: '4. 第三者提供',
              children: [
                _P(
                  '運営者は、法令に基づく場合を除き、ユーザー情報を第三者に提供しません。ただし、上記の外部サービスを利用する際、当該サービス提供のために必要な範囲で情報が送信される場合があります。',
                ),
              ],
            ),
            const _Divider(),

            const _Section(
              title: '5. 保存期間',
              children: [
                _P(
                  'ユーザー情報は、利用目的の達成に必要な期間保存します。ユーザーがアプリを削除した場合でも、サーバー側のデータが直ちに消去されるとは限りません。削除をご希望の場合は、お問い合わせ先よりご連絡ください（運営形態により対応方法が異なる場合があります）。',
                ),
              ],
            ),
            const _Divider(),

            const _Section(
              title: '6. ユーザーの権利',
              children: [
                _Li('プロフィール情報はアプリ内で変更できます。'),
                _Li('引き継ぎ設定（メールアドレス・パスワード）の変更は、アプリ内の案内に従って行えます。'),
                _Li('購入状態の復元は、アプリ内の「購入を復元」から行えます。'),
              ],
            ),
            const _Divider(),

            const _Section(
              title: '7. セキュリティ',
              children: [
                _P('運営者は、ユーザー情報の漏えい、滅失または毀損の防止その他の安全管理のために、合理的な措置を講じます。'),
              ],
            ),
            const _Divider(),

            const _Section(
              title: '8. 未成年の利用',
              children: [
                _P('未成年のユーザーは、親権者など法定代理人の同意を得たうえで本サービスを利用してください。'),
              ],
            ),
            const _Divider(),

            const _Section(
              title: '9. 本ポリシーの変更',
              children: [
                _P('運営者は、必要に応じて本ポリシーを変更できます。変更後の内容は、本サービス上での掲示または運営者が適切と判断する方法で周知した時点から効力を生じます。'),
              ],
            ),
            const _Divider(),

            const _Section(
              title: '10. お問い合わせ',
              children: [
                _P('運営者情報やお問い合わせ先は、アプリの提供形態に合わせて追記してください。'),
              ],
            ),

            const SizedBox(height: 24),
            Center(
              child: Text(
                '最終更新日：$_effectiveDate',
                style: const TextStyle(color: Colors.black45, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.4),
                ),
              ),
              child: Text(
                '※ 本文は雛形です。実際に利用する外部サービスや連絡先に合わせて調整してください。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _P extends StatelessWidget {
  final String text;
  const _P(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SelectableText(
      text,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(height: 1.6, color: cs.onSurface),
    );
  }
}

class _Li extends StatelessWidget {
  final String text;
  const _Li(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 7),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.55, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).dividerColor.withOpacity(0.55),
      ),
    );
  }
}