import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WeeklyLibraryPage extends StatefulWidget {
  const WeeklyLibraryPage({super.key});

  @override
  State<WeeklyLibraryPage> createState() => _WeeklyLibraryPageState();
}

class _WeeklyLibraryPageState extends State<WeeklyLibraryPage> {
  int? _selectedYear;
  List<int> _yearOptions = [];

  bool _isLoading = false;
  List<_WeekEntry> _weeklyEntries = [];

  @override
  void initState() {
    super.initState();
    _loadYearOptions();
  }

  Future<void> _loadYearOptions() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      setState(() {
        _yearOptions = [];
        _selectedYear = null;
        _weeklyEntries = [];
      });
      return;
    }

    try {
      final res = await client
          .from('entries')
          .select('week_start_date')
          .eq('user_id', user.id)
          .eq('chapter_type', 'weekly');

      final list = (res as List).cast<Map<String, dynamic>>();
      final years = <int>{};

      for (final row in list) {
        final value = row['week_start_date'];
        if (value == null) continue;
        final dt = DateTime.tryParse(value.toString());
        if (dt == null) continue;
        years.add(dt.year);
      }

      if (years.isEmpty) {
        final now = DateTime.now();
        setState(() {
          _yearOptions = [now.year];
          _selectedYear = now.year;
          _weeklyEntries = [];
        });
        return;
      }

      final sortedYears = years.toList()..sort();
      setState(() {
        _yearOptions = sortedYears;
        _selectedYear = sortedYears.last;
      });

      // 選択された年に対して週まとめを読み込む
      await _loadWeeklyEntries();
    } catch (e) {
      debugPrint('Failed to load weekly year options: $e');
      setState(() {
        _yearOptions = [];
        _selectedYear = null;
        _weeklyEntries = [];
      });
    }
  }

  Future<void> _loadWeeklyEntries() async {
    if (_selectedYear == null) {
      setState(() {
        _weeklyEntries = [];
      });
      return;
    }

    final year = _selectedYear!;
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      setState(() {
        _weeklyEntries = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final startOfYear = DateTime(year, 1, 1);
      final startOfNextYear = DateTime(year + 1, 1, 1);

      final res = await client
          .from('entries')
          .select('title, body, week_start_date')
          .eq('user_id', user.id)
          .eq('chapter_type', 'weekly')
          .gte('week_start_date', startOfYear.toIso8601String())
          .lt('week_start_date', startOfNextYear.toIso8601String())
          .order('week_start_date', ascending: true);

      final list = (res as List).cast<Map<String, dynamic>>();

      final entries = <_WeekEntry>[];
      for (final row in list) {
        final value = row['week_start_date'];
        if (value == null) continue;
        final dt = DateTime.tryParse(value.toString());
        if (dt == null) continue;
        final title = row['title'] as String?;
        final body = row['body'] as String?;
        entries.add(_WeekEntry(
          startDate: dt,
          title: title,
          body: body,
        ));
      }

      setState(() {
        _weeklyEntries = entries;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to load weekly entries: $e');
      setState(() {
        _weeklyEntries = [];
        _isLoading = false;
      });
    }
  }

  void _showYearPicker(BuildContext context) {
    FocusScope.of(context).requestFocus(FocusNode());

    if (_yearOptions.isEmpty) return;

    Future.delayed(const Duration(milliseconds: 100), () {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        builder: (BuildContext context) {
          int tempIndex =
              _yearOptions.indexOf(_selectedYear ?? _yearOptions.first);
          if (tempIndex < 0) tempIndex = 0;

          return SizedBox(
            height: 300,
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'キャンセル',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                      const Text(
                        '年を選択',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedYear = _yearOptions[tempIndex];
                          });
                          Navigator.pop(context);
                          _loadWeeklyEntries();
                        },
                        child: const Text(
                          '決定',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: CupertinoPicker(
                    backgroundColor: Colors.white,
                    itemExtent: 40.0,
                    scrollController: FixedExtentScrollController(
                      initialItem: tempIndex,
                    ),
                    onSelectedItemChanged: (int index) {
                      tempIndex = index;
                    },
                    children: _yearOptions.map((y) {
                      return Center(
                        child: Text(
                          '$y 年',
                          style: const TextStyle(fontSize: 22),
                        ),
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

  List<_MonthlyWeekGroup> _buildMonthlyGroups() {
    if (_selectedYear == null) return [];
    final year = _selectedYear!;
    final Map<int, List<_WeekEntry>> byMonth = {};
    for (final entry in _weeklyEntries) {
      final weekStart = entry.startDate;
      final weekEnd = weekStart.add(const Duration(days: 6));
      for (var month = 1; month <= 12; month++) {
        final monthStart = DateTime(year, month, 1);
        final monthEnd = DateTime(year, month + 1, 1).subtract(const Duration(days: 1));
        final noOverlap = weekEnd.isBefore(monthStart) || weekStart.isAfter(monthEnd);
        if (!noOverlap) {
          byMonth.putIfAbsent(month, () => <_WeekEntry>[]).add(entry);
        }
      }
    }
    final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    return months
        .map(
          (m) => _MonthlyWeekGroup(
            month: m,
            weeks: (byMonth[m]!..sort(
                  (a, b) => a.startDate.compareTo(b.startDate),
                )),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leadingWidth: 130,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Text(
                '月の本棚へ',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
          ],
        ),
        title: Text(
          '週の本棚',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _yearOptions.isEmpty
                        ? null
                        : () => _showYearPicker(context),
                    child: InputDecorator(
                      isEmpty: _yearOptions.isEmpty,
                      decoration: const InputDecoration(
                        labelText: '年',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        _selectedYear != null
                            ? '${_selectedYear!} 年'
                            : '年を選択',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : Builder(
                    builder: (context) {
                      final groups = _buildMonthlyGroups();
                      if (_selectedYear == null || groups.isEmpty) {
                        return Center(
                          child: Text(
                            'この年の週まとめはまだありません',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: groups.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final group = groups[index];
                          final month = group.month;
                          final weeks = group.weeks;

                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                            color: theme.colorScheme.surfaceVariant
                                .withOpacity(0.6),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 12, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 月ヘッダー
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_view_week,
                                        size: 20,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$month月',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${weeks.length}本',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: theme.colorScheme.outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // 週の本たち
                                  ...weeks.map(
                                    (w) {
                                      return InkWell(
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => WeeklySummaryPage(
                                                startDate: w.startDate,
                                                title: w.title,
                                                body: w.body,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4.0,
                                          ),
                                          child: Row(
                                            children: [
                                              // 本っぽい色バー
                                              Container(
                                                width: 4,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                  color: theme
                                                      .colorScheme.primary
                                                      .withOpacity(0.7),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      w.title ??
                                                          '第${w.weekNumberWithinMonth}週のまとめ',
                                                      style: theme.textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${w.startLabel} 〜 ${w.endLabel}',
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        color: theme
                                                            .colorScheme
                                                            .outline,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Icon(
                                                Icons.chevron_right,
                                                size: 18,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WeekEntry {
  final DateTime startDate;
  final String? title;
  final String? body;

  _WeekEntry({
    required this.startDate,
    this.title,
    this.body,
  });

  String get startLabel => '${startDate.month}/${startDate.day}';

  String get endLabel {
    final end = startDate.add(const Duration(days: 6));
    return '${end.month}/${end.day}';
  }

  int get weekNumberWithinMonth {
    return ((startDate.day - 1) ~/ 7) + 1;
  }
}

class _MonthlyWeekGroup {
  final int month;
  final List<_WeekEntry> weeks;

  _MonthlyWeekGroup({
    required this.month,
    required this.weeks,
  });
}

class WeeklySummaryPage extends StatelessWidget {
  final DateTime startDate;
  final String? title;
  final String? body;

  const WeeklySummaryPage({
    super.key,
    required this.startDate,
    this.title,
    this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekNumber =
        ((startDate.day - 1) ~/ 7) + 1; // 月内での第何週かをざっくり算出
    final displayTitle = title ?? '第${weekNumber}週のまとめ';
    final displayBody = body ?? 'この週の本文がまだありません。';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          displayTitle,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 横幅が広い端末でも読みやすいように最大幅を制限
            final maxTextWidth =
                constraints.maxWidth > 640 ? 640.0 : constraints.maxWidth - 32;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxTextWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 画面上部に少し大きめのタイトル
                      Text(
                        displayTitle,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 本文
                      Text(
                        displayBody,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.8, // 行間を少し広めに
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}