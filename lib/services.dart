import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  bool _loading = false;
  String? _error;
  Package? _monthly;

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
    } on PurchasesErrorCode catch (e) {
      // purchases_flutter は例外が PlatformException になることがあるため、ここには来にくい
      if (!mounted) return;
      setState(() => _error = '購入に失敗しました: $e');
    } catch (e) {
      // ユーザーキャンセルはエラー扱いにしない
      final msg = e.toString();
      if (msg.contains('purchaseCancelledError') || msg.contains('PurchaseCancelled')) {
        // no-op
      } else {
        if (!mounted) return;
        setState(() => _error = '購入に失敗しました: $e');
      }
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

    // 日本のみ販売の前提：表示価格は固定（※実際の課金額はApp Store側が確定）
    const priceText = '月額 ¥300';

    return Scaffold(
      appBar: AppBar(
        title: const Text('プレミアム機能'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('キャンセル'),
          ),
        ],
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
                      : Text(isPremium ? 'プレミアムは有効です' : '$priceText でアップグレード'),
                ),
              ),
              const SizedBox(height: 8),
              if (!isPremium)
                Text(
                  '自動更新のサブスクリプションです\nいつでも解約できます\n（設定 > Apple ID > サブスクリプション）',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
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
                '購入により、利用規約およびプライバシーポリシーに同意したものとみなされます。',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
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
  static const String _androidKey = 'REVENUECAT_PUBLIC_ANDROID_KEY_HERE';

  static final ValueNotifier<bool> isPremium = ValueNotifier<bool>(false);
  static bool _configured = false;

  static Future<void> init() async {
    if (_configured) return;

    // Web は Purchases 非対応
    if (kIsWeb) {
      _configured = true;
      return;
    }

    await Purchases.setLogLevel(LogLevel.info);

    final user = Supabase.instance.client.auth.currentUser;
    final appUserId = user?.id;

    // 📱 Platform 分岐
    final apiKey = Platform.isIOS ? _iosKey : _androidKey;

    final config = PurchasesConfiguration(apiKey);
    if (appUserId != null && appUserId.isNotEmpty) {
      config.appUserID = appUserId;
    }

    await Purchases.configure(config);

    // customerInfo 更新を監視
    Purchases.addCustomerInfoUpdateListener((info) {
      applyCustomerInfo(info);
    });

    // 初回状態を反映
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