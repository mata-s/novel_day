import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EntriesPage extends StatefulWidget {
  const EntriesPage({super.key});

  @override
  State<EntriesPage> createState() => _EntriesPageState();
}

class _EntriesPageState extends State<EntriesPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _entries = [];
  late int _selectedYear;
  late int _selectedMonth;
  List<int> _availableYears = [];
  Map<int, List<int>> _availableMonthsByYear = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _loadYearMonthOptionsAndEntries();
  }

  Future<void> _loadYearMonthOptionsAndEntries() async {
    await _loadYearMonthOptions();
    await _loadEntries();
  }

  Future<void> _loadYearMonthOptions() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      setState(() {
        _availableYears = [];
        _availableMonthsByYear = {};
      });
      return;
    }

    try {
      final data = await client
          .from('entries')
          .select('created_at, week_start_date, month_start_date')
          .eq('user_id', user.id);

      final yearSet = <int>{};
      final monthMap = <int, Set<int>>{};

      for (final raw in data as List) {
        final row = raw as Map<String, dynamic>;
        final createdAt = row['created_at'];
        if (createdAt == null) continue;

        // 週まとめ・月まとめは除外して、日々のエントリだけを対象にする
        if (row['week_start_date'] != null || row['month_start_date'] != null) {
          continue;
        }

        DateTime dt;
        try {
          dt = DateTime.parse(createdAt.toString());
        } catch (_) {
          continue;
        }

        final y = dt.year;
        final m = dt.month;
        yearSet.add(y);
        monthMap.putIfAbsent(y, () => <int>{}).add(m);
      }

      final years = yearSet.toList()..sort();
      final monthsByYear = <int, List<int>>{};
      for (final entry in monthMap.entries) {
        final months = entry.value.toList()..sort();
        monthsByYear[entry.key] = months;
      }

      int selectedYear = _selectedYear;
      int selectedMonth = _selectedMonth;

      if (years.isNotEmpty) {
        if (!years.contains(selectedYear)) {
          selectedYear = years.last;
        }
        final months = monthsByYear[selectedYear] ?? <int>[];
        if (months.isNotEmpty) {
          if (!months.contains(selectedMonth)) {
            selectedMonth = months.last;
          }
        }
      }

      setState(() {
        _availableYears = years;
        _availableMonthsByYear = monthsByYear;
        _selectedYear = selectedYear;
        _selectedMonth = selectedMonth;
      });
    } catch (e) {
      debugPrint('Failed to load year/month options: $e');
      // 年月情報が取れなくても致命的ではないので、ここでは SnackBar は出さない
    }
  }

  Future<void> _loadEntries() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      setState(() {
        _entries = [];
        _isLoading = false;
      });
      return;
    }

    try {
      // 選択中の年・月の範囲で絞り込む
      final start = DateTime(_selectedYear, _selectedMonth, 1);
      final end = DateTime(
        _selectedMonth == 12 ? _selectedYear + 1 : _selectedYear,
        _selectedMonth == 12 ? 1 : _selectedMonth + 1,
        1,
      );

      final data = await client
          .from('entries')
          .select()
          .eq('user_id', user.id)
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String())
          .order('created_at', ascending: false);

      final list = (data as List)
          .cast<Map<String, dynamic>>()
          .where((row) =>
              row['title'] != null &&
              row['body'] != null &&
              row['week_start_date'] == null &&
              row['month_start_date'] == null)
          .toList();

      setState(() {
        _entries = list;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to load entries: $e');
      if (!mounted) return;
      setState(() {
        _entries = [];
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('記録の読み込みに失敗しました: $e')),
      );
    }
  }

  String _formatDate(dynamic value) {
    try {
      if (value == null) return '';
      // Supabase側のタイムスタンプ文字列をそのままパースして日付を取り出す
      final dt = DateTime.parse(value.toString());

      return '${dt.year}年${dt.month}月${dt.day}日';
    } catch (_) {
      return '';
    }
  }

  String _buildStyleLabel(String? style) {
    switch (style) {
      case 'A':
        return 'やわらか文学';
      case 'B':
        return '詩的・静けさ';
      case 'C':
        return '切ない物語';
      default:
        return '';
    }
  }

  Color _styleColor(BuildContext context, String? style) {
    final scheme = Theme.of(context).colorScheme;
    switch (style) {
      case 'A':
        return scheme.primary.withOpacity(0.85);
      case 'B':
        return scheme.tertiary.withOpacity(0.85);
      case 'C':
        return scheme.secondary.withOpacity(0.85);
      default:
        return scheme.outlineVariant.withOpacity(0.6);
    }
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'まだ小説の記録がありません',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '「今日」のタブでメモを書いて、小さな物語をつくってみてね。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadYearMonthOptions();
        await _loadEntries();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(12.0),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          final title = entry['title'] as String? ?? '';
          final body = entry['body'] as String? ?? '';
          final memo = entry['memo'] as String? ?? '';
          final style = entry['style'] as String?;
          final createdAt = _formatDate(entry['created_at']);

          final bodyPreview =
              body.length > 80 ? '${body.substring(0, 80)}…' : body;

          final scheme = Theme.of(context).colorScheme;
          final accent = _styleColor(context, style);

          return Card(
            elevation: 0,
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                // モダンなボトムシートで詳細表示
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  builder: (context) {
                    return DraggableScrollableSheet(
                      expand: false,
                      initialChildSize: 0.7,
                      minChildSize: 0.4,
                      maxChildSize: 0.95,
                      builder: (context, scrollController) {
                        return SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 40,
                                  height: 4,
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: scheme.outlineVariant,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                              if (createdAt.isNotEmpty || style != null)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (createdAt.isNotEmpty)
                                      Text(
                                        createdAt,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.outline,
                                            ),
                                      ),
                                    if (style != null && style.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accent.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.auto_awesome,
                                              size: 14,
                                              color: accent,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _buildStyleLabel(style),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: accent,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              const SizedBox(height: 12),
                              Text(
                                title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              if (memo.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Text(
                                  'メモ',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: scheme.outline,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  memo,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(height: 1.4),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Text(
                                '小説',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: scheme.outline,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                body,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(height: 1.6),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.surface,
                      scheme.surfaceVariant.withOpacity(0.5),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左にスタイルのアクセントバー
                      Container(
                        width: 4,
                        height: 64,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 本文エリア
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (createdAt.isNotEmpty || style != null)
                              Row(
                                children: [
                                  if (createdAt.isNotEmpty)
                                    Text(
                                      createdAt,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.outline,
                                          ),
                                    ),
                                  if (createdAt.isNotEmpty && style != null)
                                    const SizedBox(width: 6),
                                  if (style != null && style.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: accent.withOpacity(0.12),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        _buildStyleLabel(style),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: accent,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                            if (createdAt.isNotEmpty || style != null)
                              const SizedBox(height: 6),
                            Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            if (memo.isNotEmpty)
                              Text(
                                memo,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: scheme.outline,
                                    ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (memo.isNotEmpty) const SizedBox(height: 4),
                            Text(
                              bodyPreview,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(height: 1.35),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<int> _monthsForSelectedYear() {
    return _availableMonthsByYear[_selectedYear] ?? const <int>[];
  }

  void _showYearPicker(BuildContext context) {
    FocusScope.of(context).requestFocus(FocusNode());

    if (_availableYears.isEmpty) return;

    Future.delayed(const Duration(milliseconds: 100), () {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        builder: (BuildContext context) {
          int tempIndex = _availableYears.indexOf(_selectedYear);
          if (tempIndex < 0) tempIndex = 0;

          return SizedBox(
            height: 300,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('キャンセル', style: TextStyle(fontSize: 16)),
                      ),
                      const Text(
                        '年を選択',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            final year = _availableYears[tempIndex];
                            _selectedYear = year;
                            final months =
                                _availableMonthsByYear[year] ?? const <int>[];
                            if (months.isNotEmpty &&
                                !months.contains(_selectedMonth)) {
                              _selectedMonth = months.last;
                            }
                            _isLoading = true;
                          });
                          Navigator.pop(context);
                          _loadEntries();
                        },
                        child: const Text('決定',
                            style: TextStyle(fontSize: 16, color: Colors.blue)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: CupertinoPicker(
                    backgroundColor: Colors.white,
                    itemExtent: 40.0,
                    scrollController:
                        FixedExtentScrollController(initialItem: tempIndex),
                    onSelectedItemChanged: (int index) {
                      tempIndex = index;
                    },
                    children: _availableYears.map((y) {
                      return Center(
                        child: Text('$y年', style: const TextStyle(fontSize: 22)),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }

  void _showMonthPicker(BuildContext context) {
    FocusScope.of(context).requestFocus(FocusNode());

    final months = _monthsForSelectedYear();
    if (months.isEmpty) return;

    Future.delayed(const Duration(milliseconds: 100), () {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        builder: (BuildContext context) {
          int tempIndex = months.indexOf(_selectedMonth);
          if (tempIndex < 0) tempIndex = months.length - 1;

          return SizedBox(
            height: 300,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('キャンセル', style: TextStyle(fontSize: 16)),
                      ),
                      const Text(
                        '月を選択',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedMonth = months[tempIndex];
                            _isLoading = true;
                          });
                          Navigator.pop(context);
                          _loadEntries();
                        },
                        child: const Text('決定',
                            style: TextStyle(fontSize: 16, color: Colors.blue)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: CupertinoPicker(
                    backgroundColor: Colors.white,
                    itemExtent: 40.0,
                    scrollController:
                        FixedExtentScrollController(initialItem: tempIndex),
                    onSelectedItemChanged: (int index) {
                      tempIndex = index;
                    },
                    children: months.map((m) {
                      return Center(
                        child: Text('$m月', style: const TextStyle(fontSize: 22)),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final monthsForYear = _monthsForSelectedYear();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _availableYears.isEmpty
                      ? null
                      : () => _showYearPicker(context),
                  child: InputDecorator(
                    isEmpty: _availableYears.isEmpty,
                    decoration: const InputDecoration(
                      labelText: '年',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: Text(
                      _availableYears.isEmpty ? 'データなし' : '$_selectedYear年',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: monthsForYear.isEmpty
                      ? null
                      : () => _showMonthPicker(context),
                  child: InputDecorator(
                    isEmpty: monthsForYear.isEmpty,
                    decoration: const InputDecoration(
                      labelText: '月',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: Text(
                      monthsForYear.isEmpty ? '—' : '$_selectedMonth月',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildBody(context),
        ),
      ],
    );
  }
}
