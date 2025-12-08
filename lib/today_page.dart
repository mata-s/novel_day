import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lottie/lottie.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final TextEditingController _memoController = TextEditingController();
  String _selectedStyle = 'A';
  String? _generatedTitle;
  String? _generatedBody;
  bool _isLoading = false;
  bool _canGenerateWeekly = false;
  bool _canGenerateMonthly = false;

  @override
  void initState() {
    super.initState();
    _updateWeeklyButtonState();
    _updateMonthlyButtonState();
    _loadTodayEntry();
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  // ===============================
  // 週の開始（月曜）を求める
  // ===============================
  DateTime _startOfWeek(DateTime dt) {
    final weekday = dt.weekday; // 月=1〜日=7
    final dateOnly = DateTime(dt.year, dt.month, dt.day);
    return dateOnly.subtract(Duration(days: weekday - 1));
  }

  // ===============================
  // 月の第何週目かを求める（A: 月ごとの週）
  // ===============================
  int _weekOfMonth(DateTime date) {
    // 月の1日
    final firstDayOfMonth = DateTime(date.year, date.month, 1);

    // 月曜始まりのオフセット（DateTime: 月=1〜日=7）
    final int firstWeekday = firstDayOfMonth.weekday; // 1〜7
    final int offset =
        firstWeekday == DateTime.monday ? 0 : (firstWeekday - DateTime.monday);

    // (日付 + オフセット) / 7 を切り上げ → 第何週か
    return ((date.day + offset) / 7).ceil();
  }

  // ===============================
  // 週のまとめボタンの表示可否を更新
  // ===============================
  Future<void> _updateWeeklyButtonState() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _canGenerateWeekly = false;
      });
      return;
    }

    try {
      final now = DateTime.now();
      final thisWeekStart = _startOfWeek(now);
      final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
      final lastWeekEnd = thisWeekStart;
      final lastWeekStartStr =
          lastWeekStart.toIso8601String().substring(0, 10); // YYYY-MM-DD

      // 先週の daily が1件でもあるかチェック
      final dailyRes = await client
          .from('entries')
          .select('id')
          .eq('user_id', user.id)
          .eq('chapter_type', 'daily')
          .gte('created_at', lastWeekStart.toUtc().toIso8601String())
          .lt('created_at', lastWeekEnd.toUtc().toIso8601String())
          .limit(1);

      final dailyList = (dailyRes as List).cast<Map<String, dynamic>>();
      if (dailyList.isEmpty) {
        if (!mounted) return;
        setState(() {
          _canGenerateWeekly = false;
        });
        return;
      }

      // 先週分の weekly がすでにあるかチェック
      final weekly = await client
          .from('entries')
          .select('id')
          .eq('user_id', user.id)
          .eq('chapter_type', 'weekly')
          .eq('week_start_date', lastWeekStartStr)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _canGenerateWeekly = (weekly == null);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _canGenerateWeekly = false;
      });
    }
  }

  // ===============================
  // 月の短編ボタンの表示可否を更新
  // ===============================
  Future<void> _updateMonthlyButtonState() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _canGenerateMonthly = false;
      });
      return;
    }

    try {
      final now = DateTime.now();

      // 今月の1日と先月の1日を求める
      final thisMonthStart = DateTime(now.year, now.month, 1);
      final lastMonthStart = now.month == 1
          ? DateTime(now.year - 1, 12, 1)
          : DateTime(now.year, now.month - 1, 1);

      final lastMonthStartUtc = lastMonthStart.toUtc().toIso8601String();
      final thisMonthStartUtc = thisMonthStart.toUtc().toIso8601String();

      final lastMonthStartStr =
          lastMonthStart.toIso8601String().substring(0, 10); // YYYY-MM-DD

      // 先月の daily が1件でもあるかチェック
      final dailyRes = await client
          .from('entries')
          .select('id')
          .eq('user_id', user.id)
          .eq('chapter_type', 'daily')
          .gte('created_at', lastMonthStartUtc)
          .lt('created_at', thisMonthStartUtc)
          .limit(1);

      final dailyList = (dailyRes as List).cast<Map<String, dynamic>>();
      if (dailyList.isEmpty) {
        if (!mounted) return;
        setState(() {
          _canGenerateMonthly = false;
        });
        return;
      }

      // 先月分の monthly がすでにあるかチェック（月初日で判定）
      final monthly = await client
          .from('entries')
          .select('id')
          .eq('user_id', user.id)
          .eq('chapter_type', 'monthly')
          .eq('month_start_date', lastMonthStartStr)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _canGenerateMonthly = (monthly == null);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _canGenerateMonthly = false;
      });
    }
  }

  // ===============================
  // 今日分の小説があればロードしてカード表示にする
  // ===============================
  Future<void> _loadTodayEntry() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      return;
    }

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final res = await client
          .from('entries')
          .select()
          .eq('user_id', user.id)
          .eq('chapter_type', 'daily')
          .gte('created_at', startOfDay.toUtc().toIso8601String())
          .lt('created_at', endOfDay.toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1);

      final list = (res as List).cast<Map<String, dynamic>>();

      if (list.isEmpty) {
        // 今日まだ小説がなければ何もしない（メモ入力UIを出す）
        return;
      }

      final entry = list.first;
      final title = entry['title'] as String? ?? '今日の物語';
      final body = entry['body'] as String? ?? '';

      if (!mounted) return;
      setState(() {
        _generatedTitle = title;
        _generatedBody = body;
      });
    } catch (e) {
      // エラー時は何もしない（メモ入力UIのまま）
      debugPrint('Failed to load today entry: $e');
    }
  }

  // ===============================
  // 週のまとめ章を生成
  // ===============================
  Future<void> _generateWeeklyChapter() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログイン情報が見つかりません')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // ローディングダイアログ表示（週まとめ用）
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const GeneratingDialog(type: 'weekly'),
    );

    try {
      // 週の範囲
      final now = DateTime.now();
      final thisWeekStart = _startOfWeek(now);
      final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
      final lastWeekEnd = thisWeekStart;
      final lastWeekStartStr = lastWeekStart.toIso8601String().substring(0, 10);
      final weekOfMonth = _weekOfMonth(lastWeekStart);

      // 先週の daily を取得
      final entryList = await client
          .from('entries')
          .select()
          .eq('user_id', user.id)
          .eq('chapter_type', 'daily')
          .gte('created_at', lastWeekStart.toUtc().toIso8601String())
          .lt('created_at', lastWeekEnd.toUtc().toIso8601String())
          .order('created_at', ascending: true);

      final dailyList = (entryList as List).cast<Map<String, dynamic>>();

      if (dailyList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('先週の記録がまだありません')),
        );
        return;
      }

      // すでに weekly があるかチェック
      final weekly = await client
          .from('entries')
          .select()
          .eq('user_id', user.id)
          .eq('chapter_type', 'weekly')
          .eq('week_start_date', lastWeekStartStr)
          .maybeSingle();

      if (weekly != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('先週のまとめ章は作成済みです')),
        );
        return;
      }

      // プロフィール読み取り
      final profile = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final firstPerson =
          (profile != null &&
                  profile['first_person'] is String &&
                  profile['first_person'].toString().trim().isNotEmpty)
              ? profile['first_person'] as String
              : '僕';

      final userName =
          (profile != null &&
                  profile['name'] is String &&
                  profile['name'].toString().trim().isNotEmpty)
              ? profile['name'] as String
              : null;

      // これまでの weekly 章の件数から「第◯巻」を決める（weekly だけカウント）
      final weeklyRes = await client
          .from('entries')
          .select('id')
          .eq('user_id', user.id)
          .eq('chapter_type', 'weekly');

      final weeklyList =
          (weeklyRes as List).cast<Map<String, dynamic>>();
      final volumeNumber = weeklyList.length + 1;

      // Edge Function に投げる形式（entries だけ抽出）
      final entriesForAi = dailyList
          .map((e) => {
                'created_at': e['created_at'],
                'memo': e['memo'],
                'body': e['body'],
              })
          .toList();

      // 週まとめ生成
      final res = await client.functions.invoke(
        'generate_weekly_chapter',
        body: {
          'entries': entriesForAi,
          'persona': {
            'first_person': firstPerson,
            'name': userName,
          },
        },
      );

      final data = res.data as Map<String, dynamic>?;

      if (data == null || data['body'] == null) {
        throw Exception('特別章の生成に失敗しました');
      }

      // 本文は AI から受け取り、タイトルはアプリ側で決める
      final body = data['body'] as String;

      final title =
          '第${weekOfMonth}週 まとめ章（特別章）第${volumeNumber}巻';

      // entries に weekly として保存
      await client.from('entries').insert({
        'user_id': user.id,
        'memo': '第${weekOfMonth}週 まとめ章',
        'style': 'W',
        'title': title,
        'body': body,
        'chapter_type': 'weekly',
        'week_start_date': lastWeekStartStr,
        'volume': volumeNumber,
        'created_at': DateTime.now().toIso8601String(),
      });

      await _updateWeeklyButtonState();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先週のまとめ章を作成しました')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('特別章の生成に失敗しました: $e')),
      );
    } finally {
      if (!mounted) return;
      Navigator.of(context).pop(); // ダイアログを閉じる
      setState(() => _isLoading = false);
    }
  }

  // ===============================
  // 月の短編を生成
  // ===============================
  Future<void> _generateMonthlyChapter() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ログイン情報が見つかりません')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // ローディングダイアログ表示（月の短編用）
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const GeneratingDialog(type: 'monthly'),
    );

    try {
      final now = DateTime.now();

      // 今月の1日と先月の1日を求める
      final thisMonthStart = DateTime(now.year, now.month, 1);
      final lastMonthStart = now.month == 1
          ? DateTime(now.year - 1, 12, 1)
          : DateTime(now.year, now.month - 1, 1);

      final lastMonthStartUtc = lastMonthStart.toUtc().toIso8601String();
      final thisMonthStartUtc = thisMonthStart.toUtc().toIso8601String();

      final monthStartStr =
          lastMonthStart.toIso8601String().substring(0, 10); // YYYY-MM-DD

      // 先月の daily を取得
      final entryList = await client
          .from('entries')
          .select()
          .eq('user_id', user.id)
          .eq('chapter_type', 'daily')
          .gte('created_at', lastMonthStartUtc)
          .lt('created_at', thisMonthStartUtc)
          .order('created_at', ascending: true);

      final dailyList = (entryList as List).cast<Map<String, dynamic>>();

      if (dailyList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('先月の記録がまだありません')),
        );
        return;
      }

      // すでに先月の monthly があるかチェック（月初日で判定）
      final monthlyExisting = await client
          .from('entries')
          .select()
          .eq('user_id', user.id)
          .eq('chapter_type', 'monthly')
          .eq('month_start_date', monthStartStr)
          .maybeSingle();

      if (monthlyExisting != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('先月の短編は作成済みです')),
        );
        await _updateMonthlyButtonState();
        return;
      }

      // プロフィール読み取り
      final profile = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final firstPerson =
          (profile != null &&
                  profile['first_person'] is String &&
                  profile['first_person'].toString().trim().isNotEmpty)
              ? profile['first_person'] as String
              : '僕';

      final userName =
          (profile != null &&
                  profile['name'] is String &&
                  profile['name'].toString().trim().isNotEmpty)
              ? profile['name'] as String
              : null;

      final entriesForAi = dailyList
          .map((e) => {
                'created_at': e['created_at'],
                'memo': e['memo'],
                'body': e['body'],
              })
          .toList();

      // 月の短編生成 Edge Function 呼び出し
      final res = await client.functions.invoke(
        'generate_monthly_chapter',
        body: {
          'entries': entriesForAi,
          'persona': {
            'first_person': firstPerson,
            'name': userName,
          },
        },
      );

      final data = res.data as Map<String, dynamic>?;

      if (data == null || data['body'] == null) {
        throw Exception('月の短編の生成に失敗しました');
      }

      final title = (data['title'] as String?) ?? '今月の物語';
      final body = data['body'] as String;

      final monthLabel = '${lastMonthStart.year}年${lastMonthStart.month}月';

      await client.from('entries').insert({
        'user_id': user.id,
        'memo': '$monthLabelの短編',
        'style': 'M',
        'title': title,
        'body': body,
        'chapter_type': 'monthly',
        'month_start_date': monthStartStr,
        'created_at': DateTime.now().toIso8601String(),
      });

      await _updateMonthlyButtonState();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$monthLabelの短編を作成しました')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('月の短編の生成に失敗しました: $e')),
      );
    } finally {
      if (!mounted) return;
      Navigator.of(context).pop(); // ダイアログを閉じる
      setState(() => _isLoading = false);
    }
  }

  // ===============================
  // 今日の小説生成（既存機能）
  // ===============================
  Future<void> _onGeneratePressed() async {
    final memo = _memoController.text.trim();
    if (memo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('まずは今日のメモを書いてね。')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _generatedTitle = null;
      _generatedBody = null;
    });

    // ローディングダイアログ表示（今日の物語用）
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const GeneratingDialog(type: 'daily'),
    );

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;

      if (user == null) {
        throw Exception('ユーザー情報が取得できませんでした');
      }

      final profile = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final firstPerson =
          (profile != null && profile['first_person'] is String)
              ? profile['first_person'] as String
              : '僕';
      final userName =
          (profile != null && profile['name'] is String)
              ? profile['name'] as String
              : null;

      final functions = client.functions;

      final res = await functions.invoke(
        'generate_novel',
        body: {
          'memo': memo,
          'style': _selectedStyle,
          'persona': {
            'first_person': firstPerson,
            'name': userName,
          },
        },
      );

      final data = res.data as Map<String, dynamic>?;

      if (data == null || data['body'] == null) {
        throw Exception('小説の生成に失敗しました');
      }

      final title = (data['title'] as String?) ?? '今日の物語';
      final body = data['body'] as String;

      await Supabase.instance.client.from('entries').insert({
        'user_id': user.id,
        'memo': memo,
        'style': _selectedStyle,
        'title': title,
        'body': body,
        'chapter_type': 'daily',
        'created_at': DateTime.now().toIso8601String(),
      });

      setState(() {
        _generatedTitle = title;
        _generatedBody = body;
      });

      await _updateWeeklyButtonState();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('小説の生成に失敗しました: $e')),
      );
    } finally {
      if (!mounted) return;
      Navigator.of(context).pop(); // ダイアログを閉じる
      setState(() => _isLoading = false);
    }
  }

  // ===============================
  // UI
  // ===============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: (_canGenerateWeekly || _canGenerateMonthly)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_canGenerateMonthly)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: FloatingActionButton.extended(
                      onPressed:
                          _isLoading ? null : _generateMonthlyChapter,
                      icon: const Icon(Icons.menu_book),
                      label: const Text('月の短編'),
                    ),
                  ),
                if (_canGenerateWeekly)
                  FloatingActionButton.extended(
                    onPressed: _isLoading ? null : _generateWeeklyChapter,
                    icon: const Icon(Icons.auto_stories),
                    label: const Text('週のまとめ章'),
                  ),
              ],
            )
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: _generatedTitle == null || _generatedBody == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '今日のメモ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '・今日いちばん印象に残ったこと\n'
                    '・軽く日記みたいに、2〜3行でもOK\n'
                    '・箇条書きでも、まとまってなくても大丈夫だよ',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _memoController,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: '例）\n'
                          '・8時に起きて遅刻した\n'
                          '・上司に怒られたけど空がきれいだった\n'
                          '・帰りに食べたご飯が思った以上においしかった\n'
                          '・晴れ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '文体スタイル',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const <ButtonSegment<String>>[
                      ButtonSegment<String>(
                        value: 'A',
                        label: Text('やわらか文学系'),
                        icon: Icon(Icons.wb_sunny_outlined),
                      ),
                      ButtonSegment<String>(
                        value: 'B',
                        label: Text('詩的・静けさ'),
                        icon: Icon(Icons.nights_stay_outlined),
                      ),
                      ButtonSegment<String>(
                        value: 'C',
                        label: Text('切ない物語系'),
                        icon: Icon(Icons.auto_awesome),
                      ),
                    ],
                    selected: <String>{_selectedStyle},
                    onSelectionChanged: (newSelection) {
                      setState(() {
                        _selectedStyle = newSelection.first;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _onGeneratePressed,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('小説をつくる'),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 0,
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: Theme.of(context).colorScheme.surface,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 8,
                                height: 32,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '今日の物語',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            letterSpacing: 0.4,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _generatedTitle!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _generatedBody!,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  height: 1.6,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class GeneratingDialog extends StatefulWidget {
  final String type; // 'daily', 'weekly', 'monthly'

  const GeneratingDialog({super.key, required this.type});

  @override
  State<GeneratingDialog> createState() => _GeneratingDialogState();
}

class _GeneratingDialogState extends State<GeneratingDialog> {
  int step = 0;
  Timer? _timer1;
  Timer? _timer2;
  late final String _selectedLottie;

  @override
  void initState() {
    super.initState();

    final lotties = [
      'assets/lottie/writing_book1.json',
      'assets/lottie/writing_book2.json',
    ];
    _selectedLottie = lotties[Random().nextInt(lotties.length)];

    _startProgress();
  }

  void _startProgress() {
    _timer1 = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => step = 1);
      }
    });
    _timer2 = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => step = 2);
      }
    });
  }

  @override
  void dispose() {
    _timer1?.cancel();
    _timer2?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    List<String> steps;
    switch (widget.type) {
      case 'weekly':
        steps = [
          '先週の出来事を読み取っています…',
          '一週間の流れをまとめています…',
          '特別章として仕上げています…',
        ];
        break;
      case 'monthly':
        steps = [
          '先月の足跡を読み取っています…',
          '一か月の心の動きを編んでいます…',
          '月の短編として形にしています…',
        ];
        break;
      case 'daily':
      default:
        steps = [
          '今日の出来事を読み取っています…',
          '言葉を編み合わせています…',
          '物語として形にしています…',
        ];
        break;
    }

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      insetPadding: EdgeInsets.zero, // 画面全体に広げる
      child: SizedBox.expand(
        child: Stack(
          children: [
            // 背景にふわっと漂う「ことばの欠片」
            const Positioned.fill(
              child: IgnorePointer(
                child: FloatingWords(),
              ),
            ),
            // 手前にローディングコンテンツ（中央寄せ）
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 360,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final screenHeight = constraints.maxHeight;
                      // 画面の約8割を Lottie に割り当てつつ、
                      // 下にテキストとプログレスバー用のスペースを残す
                      final lottieHeight = screenHeight * 0.7;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: lottieHeight,
                            child: Lottie.asset(
                              _selectedLottie,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${step + 1} / 3',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            steps[step],
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          LinearProgressIndicator(
                            minHeight: 4,
                            backgroundColor: theme.colorScheme.surfaceVariant,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ダイアログの背景でふわっと漂う「ことばの欠片」
const List<String> _wordFragments = [
  '光',
  '雨',
  '静けさ',
  '風',
  '道',
  '朝',
  '夜',
  '温もり',
  '揺らぎ',
  '影',
  '雲',
  '鼓動',
  '足音',
  'ため息',
  '記憶',
  '窓',
  '坂道',
  '灯り',
  '波',
  '星',
  '気配',
  'まばたき',
  '約束',
  '余韻',
  '息',
  '祈り',
  '影法師',
  'ページ',
  '静寂',
  'ざわめき',
];

class FloatingWords extends StatefulWidget {
  const FloatingWords({super.key});

  @override
  State<FloatingWords> createState() => _FloatingWordsState();
}

class _FloatingWordsState extends State<FloatingWords> {
  final Random _random = Random();
  late List<_FloatingWordData> _words;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    // 最初はすべて非表示状態で準備
    _words = List.generate(
      _wordFragments.length,
      (i) => _FloatingWordData(
        text: _wordFragments[i],
        opacity: 0.0,
        position: const Offset(0, 0),
      ),
    );

    _startAnimation();
  }

  void _startAnimation() {
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;

      setState(() {
        for (int i = 0; i < _words.length; i++) {
          // 2〜3個ずつランダムに出す
          if (_random.nextDouble() < 0.25) {
            _words[i] = _words[i].copyWith(
              opacity: 1.0,
              position: _randomPosition(),
            );

            // 2秒後にフェードアウト
            Timer(const Duration(seconds: 2), () {
              if (!mounted) return;
              setState(() {
                _words[i] = _words[i].copyWith(opacity: 0.0);
              });
            });
          }
        }
      });
    });
  }

  Offset _randomPosition() {
    return Offset(
      _random.nextDouble(), // 横方向
      _random.nextDouble(), // 縦方向
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Stack(
          children: [
            for (final w in _words)
              Positioned(
                left: w.position.dx * (width - 40),
                top: w.position.dy * (height - 40),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 500),
                  opacity: w.opacity,
                  child: Text(
                    w.text,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// データモデル
class _FloatingWordData {
  final String text;
  final double opacity;
  final Offset position;

  const _FloatingWordData({
    required this.text,
    required this.opacity,
    required this.position,
  });

  _FloatingWordData copyWith({
    String? text,
    double? opacity,
    Offset? position,
  }) {
    return _FloatingWordData(
      text: text ?? this.text,
      opacity: opacity ?? this.opacity,
      position: position ?? this.position,
    );
  }
}