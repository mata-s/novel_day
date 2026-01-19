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
    if (!mounted) return;
    await _loadEntries();
  }

  Future<void> _loadYearMonthOptions() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _availableYears = [];
        _availableMonthsByYear = {};
      });
      return;
    }

    try {
      final data = await client
          .from('entries')
          .select('date_key, chapter_type')
          .eq('user_id', user.id);

      if (!mounted) return;

      final yearSet = <int>{};
      final monthMap = <int, Set<int>>{};

      for (final raw in data as List) {
        final row = raw as Map<String, dynamic>;

        // 日々の記録だけ対象（weekly/monthly は除外）
        final chapterType = row['chapter_type']?.toString();
        if (chapterType != 'daily') continue;

        final dateKey = row['date_key']?.toString();
        if (dateKey == null || dateKey.isEmpty) continue;

        // date_key: "YYYY-MM-DD"
        final parts = dateKey.split('-');
        if (parts.length != 3) continue;

        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (y == null || m == null) continue;

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

      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _entries = [];
        _isLoading = false;
      });
      return;
    }

    try {
      // date_key(YYYY-MM-DD) で絞り込む（JSTズレ回避）
      String two(int v) => v.toString().padLeft(2, '0');

      // 月末日を求める: 次月0日 = 当月最終日
      final lastDay = DateTime(_selectedYear, _selectedMonth + 1, 0).day;

      final startKey = '${_selectedYear}-${two(_selectedMonth)}-01';
      final endKey = '${_selectedYear}-${two(_selectedMonth)}-${two(lastDay)}';

      final data = await client
          .from('entries')
          .select()
          .eq('user_id', user.id)
          .eq('chapter_type', 'daily')
          .gte('date_key', startKey)
          .lte('date_key', endKey)
          .order('date_key', ascending: false)
          .order('created_at', ascending: false);

      if (!mounted) return;

      final list = (data as List)
          .cast<Map<String, dynamic>>()
          .where((row) =>
              row['title'] != null &&
              row['body'] != null &&
              row['chapter_type'] == 'daily' &&
              row['date_key'] != null)
          .toList();

      if (!mounted) return;
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

      final s = value.toString();

      // date_key: "YYYY-MM-DD"
      if (!s.contains('T') && s.contains('-')) {
        final parts = s.split('-');
        if (parts.length >= 3) {
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          if (y != null && m != null && d != null) {
            return '${y}年${m}月${d}日';
          }
        }
      }

      // created_at fallback: convert to local to avoid off-by-one display
      final dt = DateTime.parse(s).toLocal();
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
          final createdAt = _formatDate(entry['date_key'] ?? entry['created_at']);

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
                    decoration: InputDecoration(
                      labelText: _availableYears.isEmpty ? null : '年',
                      hintText: _availableYears.isEmpty ? 'データなし' : null,
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: Text(
                      _availableYears.isEmpty ? '' : '$_selectedYear年',
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
                    decoration: InputDecoration(
                      labelText: monthsForYear.isEmpty ? null : '月',
                      hintText: monthsForYear.isEmpty ? '—' : null,
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: Text(
                      monthsForYear.isEmpty ? '' : '$_selectedMonth月',
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
