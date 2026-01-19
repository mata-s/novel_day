import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  bool _loading = false;
  String? _error;
  Package? _monthly;

  static const String _privacyPolicyUrl = 'https://novel-day-privacy.vercel.app';
  static const String _termsUrl = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('リンクを開けませんでした: $url')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 直近のユーザー情報も更新
      await PremiumManager.refresh();

      final offerings = await Purchases.getOfferings();
      // RevenueCatダッシュボードで Offering を作っていない場合もあるので安全に
      final current = offerings.current;

      Package? monthly;
      if (current != null) {
        // まずは定番の monthly を探す
        monthly = current.monthly;
        // 見つからなければ packages の先頭を使う（とりあえず購入導線が動く）
        monthly ??= current.availablePackages.isNotEmpty
            ? current.availablePackages.first
            : null;
      }

      if (!mounted) return;
      setState(() {
        _monthly = monthly;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '読み込みに失敗しました: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _purchaseMonthly() async {
    if (_monthly == null) {
      setState(() {
        _error = '購入情報が見つかりません。RevenueCatでOffering/Packageを設定してください。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final info = await Purchases.purchasePackage(_monthly!);
      await PremiumManager.applyCustomerInfo(info);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プレミアムが有効になりました')),
      );

      // 最新状態を反映
      await PremiumManager.refresh();
      if (!mounted) return;
      setState(() {});
    } on PlatformException catch (e) {
      // purchases_flutter は PlatformException を投げる
      final code = PurchasesErrorHelper.getErrorCode(e);

      // ✅ ユーザーキャンセルは「通常の終了」扱い（赤エラーは出さない）
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        // 必要なら軽い通知だけ
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('購入をキャンセルしました')),
          );
        }
        return;
      }

      if (!mounted) return;
      setState(() => _error = '購入に失敗しました: $e');
    } catch (e) {
      // その他の例外
      if (!mounted) return;
      setState(() => _error = '購入に失敗しました: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _restore() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final info = await Purchases.restorePurchases();
      await PremiumManager.applyCustomerInfo(info);

      if (!mounted) return;
      final active = PremiumManager.isPremium.value;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(active ? '購入を復元しました' : '復元できる購入がありませんでした')),
      );

      await PremiumManager.refresh();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '復元に失敗しました: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPremium = PremiumManager.isPremium.value;

    final product = _monthly?.storeProduct;

    // Fallback price text for App Review safety
    // NOTE: 実際の請求額はApp Store側で確定します
    final priceText = product?.priceString ?? '月額 ¥300';

    final planName = 'NovelDay プレミアム（自動更新・月額）';
    final periodText = '1か月';

    return Scaffold(
      appBar: AppBar(
        title: const Text('プレミアム機能'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===== イラスト枠（いったんプレースホルダ） =====
              Container(
                height: 180,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.4),
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.auto_stories_rounded,
                    size: 72,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // ===== タイトル =====
              Text(
                'NovelDay プレミアム',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                '広告なしで集中して書けて、週／月のまとめも制限なく楽しめます。',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),

              // ===== Plan summary (required for subscription apps) =====
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.5),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      planName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '期間：$periodText　/　価格：$priceText',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ===== チェックリスト枠 =====
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.5),
                  ),
                ),
                child: Column(
                  children: const [
                    _FeatureRow(text: '広告なしで小説を作成'),
                    SizedBox(height: 10),
                    _FeatureRow(text: '週のまとめを何度でも作成'),
                    SizedBox(height: 10),
                    _FeatureRow(text: '月のまとめを何度でも作成'),
                    SizedBox(height: 10),
                    _FeatureRow(text: '前日の書き忘れも記録できる'),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ===== エラー表示 =====
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.red.withOpacity(0.18)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ===== CTA =====
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: _loading ? null : (isPremium ? null : _purchaseMonthly),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isPremium ? 'プレミアムは有効です' : '$priceText で購読を開始'),
                ),
              ),
              const SizedBox(height: 8),
              if (!isPremium)
                Text(
                  '自動更新サブスクリプションです（$periodText）\n'
                  'お支払いは購入確定時に、iOSではApple ID、AndroidではGoogleアカウントに請求されます。\n'
                  '現在の期間終了の24時間以上前に解約しない限り自動更新されます。\n'
                  '解約／管理：\n'
                  'iOS：設定 > Apple ID > サブスクリプション\n'
                  'Android：Google Play ストア > プロフィール > お支払いと定期購入 > 定期購入\n'
                  '表示価格は目安で、実際の請求額は各ストアが決定します。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                ),
              const SizedBox(height: 10),

              // ===== 復元 =====
              TextButton(
                onPressed: _loading ? null : _restore,
                child: const Text('購入を復元'),
              ),

              const SizedBox(height: 8),

              // ===== フッター（小さめの規約文） =====
              Text(
                '購入により、利用規約（EULA）およびプライバシーポリシーに同意したものとみなされます。',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 6,
                children: [
                  TextButton(
                    onPressed: _loading ? null : () => _openUrl(_termsUrl),
                    child: const Text('利用規約（EULA）'),
                  ),
                  TextButton(
                    onPressed: _loading ? null : () => _openUrl(_privacyPolicyUrl),
                    child: const Text('プライバシーポリシー'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}



class _FeatureRow extends StatelessWidget {
  final String text;
  const _FeatureRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Icon(Icons.check, size: 16, color: Colors.green.shade700),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
        ),
      ],
    );
  }
}


class PremiumManager {
  static const String entitlementId = 'premium';

  // 🔑 RevenueCat Public SDK Keys
  // Dashboard → API Keys → Public SDK Key
  static const String _iosKey = 'appl_nntQeUdyFeShLCUfXehVYxnhEGU';
  static const String _androidKey = 'goog_xThCYmyzQzYkrFqYtdZiVXWWDRv';

  static final ValueNotifier<bool> isPremium = ValueNotifier<bool>(false);
  static bool _configured = false;

  static Future<void> init() async {
  if (_configured) return;

  // Web だけは課金なし
  if (kIsWeb) {
    isPremium.value = false;
    _configured = true;
    return;
  }

  await Purchases.setLogLevel(LogLevel.info);

  final user = Supabase.instance.client.auth.currentUser;
  final appUserId = user?.id;

  // ✅ iOS / Android で API キーを切り替える
  final apiKey = Platform.isAndroid ? _androidKey : _iosKey;
  final config = PurchasesConfiguration(apiKey);

  if (appUserId != null && appUserId.isNotEmpty) {
    config.appUserID = appUserId;
  }

  await Purchases.configure(config);

  Purchases.addCustomerInfoUpdateListener((info) {
    applyCustomerInfo(info);
  });

  await refresh();

  _configured = true;
}

  static Future<void> refresh() async {
    final info = await Purchases.getCustomerInfo();
    await applyCustomerInfo(info);
  }

  static Future<void> applyCustomerInfo(CustomerInfo info) async {
    final active = info.entitlements.active.containsKey(entitlementId);
    if (isPremium.value != active) {
      isPremium.value = active;
    }
  }
}