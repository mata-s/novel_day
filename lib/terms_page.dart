import 'package:flutter/material.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  static const String _effectiveDate = '2025-12-17'; // 必要なら変更

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('利用規約'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _Section(
              title: '利用規約（NovelDay）',
              children: const [
                _P(
                  '本利用規約（以下「本規約」といいます。）は、NovelDay（以下「本サービス」といいます。）の利用条件を定めるものです。ユーザーは、本規約に同意のうえ、本サービスを利用するものとします。',
                ),
              ],
            ),
            const _Divider(),

            _Section(
              title: '第1条（適用）',
              children: const [
                _Li('本規約は、本サービスの利用に関する運営者とユーザーとの間の一切の関係に適用されます。'),
                _Li('運営者が本サービス上で別途定めるルール・ガイドライン等は、本規約の一部を構成します。'),
              ],
            ),
            const _Divider(),

            _Section(
              title: '第2条（定義）',
              children: const [
                _Li('「ユーザー」：本サービスを利用するすべての者'),
                _Li('「コンテンツ」：ユーザーが本サービス上に記録・保存する文章等、ならびに本サービスにより生成される文章等'),
                _Li('「プレミアム」：本サービスの有料機能（第8条）'),
              ],
            ),
            const _Divider(),

            _Section(
              title: '第3条（利用登録・アカウント）',
              children: const [
                _Li('本サービスは、登録なし（匿名）で利用を開始できます。'),
                _Li('端末変更等によるデータ引き継ぎのため、ユーザーはメールアドレス・パスワードを設定できる場合があります。'),
                _Li('ユーザーは自己の責任においてログイン情報を管理するものとし、第三者による利用により生じた損害について運営者は責任を負いません（運営者の故意または重大な過失がある場合を除きます）。'),
              ],
            ),
            const _Divider(),

            _Section(
              title: '第4条（禁止事項）',
              children: const [
                _Li('法令または公序良俗に反する行為'),
                _Li('犯罪行為に関連する行為'),
                _Li('本サービスまたは第三者の権利（著作権、商標権、プライバシー等）を侵害する行為'),
                _Li('本サービスの運営を妨害する行為（過度な負荷、リバースエンジニアリング、不正アクセス等）'),
                _Li('その他、運営者が不適切と判断する行為'),
              ],
            ),
            const _Divider(),

            _Section(
              title: '第5条（コンテンツの取り扱い）',
              children: const [
                _Li('ユーザーが本サービスに保存するコンテンツの権利は、原則としてユーザーに帰属します。'),
                _Li('運営者は、本サービスの提供・改善・不具合対応に必要な範囲で、コンテンツを取り扱うことがあります（詳細はプライバシーポリシーに定めます）。'),
                _Li('ユーザーは自己の責任においてコンテンツを保存・管理するものとし、端末故障・誤操作等により生じた損害について運営者は責任を負いません（運営者の故意または重大な過失がある場合を除きます）。'),
              ],
            ),
            const _Divider(),

            _Section(
              title: '第6条（生成機能について）',
              children: const [
                _Li('本サービスには、入力内容等をもとに文章を生成する機能が含まれる場合があります。'),
                _Li('生成結果は機械的に作成されるものであり、正確性・完全性・特定目的への適合性等を保証するものではありません。'),
                _Li('ユーザーは、生成結果の利用（公開・共有・商用利用等）について自己の責任で判断するものとします。'),
              ],
            ),
            const _Divider(),

            _Section(
              title: '第7条（広告表示）',
              children: const [
                _Li('本サービスは、無料で提供される範囲において広告を表示する場合があります。'),
                _Li('プレミアムにより広告表示が停止される場合があります（運営者の定める仕様に従います）。'),
              ],
            ),
            const _Divider(),

            _Section(
              title: '第8条（プレミアム・課金）',
              children: const [
                _Li('ユーザーは、本サービス上の有料機能（プレミアム）を購入することで、運営者が定める特典を利用できます。'),
                _Li('プレミアムは、Apple が提供する自動更新サブスクリプションとして提供されます。'),
                _Li('解約は、端末の「設定 > Apple ID > サブスクリプション」から手続きしてください。'),
                _Li('購入の復元（リストア）が可能な場合、運営者が定める手順に従ってください。'),
                _Li('返金は Apple の規定に従います。運営者は、法律上必要な場合を除き、運営者自身による返金対応は行いません。'),
              ],
            ),
            const _Divider(),

            _Section(
              title: '第9条（サービスの変更・停止）',
              children: const [
                _P('運営者は、ユーザーへの事前通知なく、本サービスの内容の変更、提供の停止または中断を行うことがあります。'),
              ],
            ),
            const _Divider(),

            _Section(
              title: '第10条（免責事項）',
              children: const [
                _Li('運営者は、本サービスに関して、事実上または法律上の瑕疵がないことを保証しません。'),
                _Li('本サービスの利用によりユーザーに生じた損害について、運営者は責任を負いません（運営者の故意または重大な過失がある場合を除きます）。'),
                _Li('通信回線・端末・ストア障害等の外部要因により生じた損害について、運営者は責任を負いません。'),
              ],
            ),
            const _Divider(),

            _Section(
              title: '第11条（規約変更）',
              children: const [
                _P('運営者は、必要に応じて本規約を変更できます。変更後の規約は、本サービス上での掲示または運営者が適切と判断する方法で周知した時点から効力を生じます。'),
              ],
            ),
            const _Divider(),

            _Section(
              title: '第12条（準拠法・裁判管轄）',
              children: const [
                _P('本規約は日本法を準拠法とし、本サービスに関して紛争が生じた場合、運営者所在地を管轄する裁判所を専属的合意管轄とします。'),
              ],
            ),
            const _Divider(),

            const _Section(
              title: 'お問い合わせ',
              children: [
                _P('本サービスに関するお問い合わせは、以下のメールアドレスまでご連絡ください。'),
                _P('お問い合わせ窓口（運営者メール）：splingnew@gmail.com\n※ ご連絡の際は、ユーザーIDを記載いただくと対応がスムーズです。'),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                '最終更新日：$_effectiveDate',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Colors.black45),
              ),
            ),
            const SizedBox(height: 8),
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