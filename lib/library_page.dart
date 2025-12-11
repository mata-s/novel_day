import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:novel_day/monthly_chapter_page.dart';
import 'package:novel_day/weekly_library_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int? _selectedYear;
  List<int> _yearOptions = [];
  Set<int> _availableMonths = {};

  @override
  void initState() {
    super.initState();
    _loadYearOptionsAndMonths();
  }

  Future<void> _loadYearOptionsAndMonths() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      setState(() {
        _yearOptions = [];
        _selectedYear = null;
        _availableMonths = {};
      });
      return;
    }

    try {
      final res = await client
          .from('entries')
          .select('month_start_date')
          .eq('user_id', user.id)
          .eq('chapter_type', 'monthly');

      final list = (res as List).cast<Map<String, dynamic>>();
      final years = <int>{};

      for (final row in list) {
        final value = row['month_start_date'];
        if (value == null) continue;
        final dt = DateTime.tryParse(value.toString());
        if (dt == null) continue;
        years.add(dt.year);
      }

      if (years.isEmpty) {
        // データが1件もない場合は「今年のみ」を選択肢として持たせる
        final now = DateTime.now();
        setState(() {
          _yearOptions = [now.year];
          _selectedYear = now.year;
          _availableMonths = {};
        });
        return;
      }

      final sortedYears = years.toList()..sort();

      // デフォルトは最新年
      final latestYear = sortedYears.last;

      setState(() {
        _yearOptions = sortedYears;
        _selectedYear = latestYear;
      });

      // 年が決まったので、その年の月データを読み込む
      await _loadAvailableMonths();
    } catch (e) {
      // 失敗時は一旦空状態にしておく
      setState(() {
        _yearOptions = [];
        _selectedYear = null;
        _availableMonths = {};
      });
    }
  }

  Future<void> _loadAvailableMonths() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null || _selectedYear == null) {
      setState(() {
        _availableMonths = {};
      });
      return;
    }

    final start = DateTime(_selectedYear!, 1, 1);
    final end = DateTime(_selectedYear! + 1, 1, 1);

    try {
      final res = await client
          .from('entries')
          .select('month_start_date')
          .eq('user_id', user.id)
          .eq('chapter_type', 'monthly')
          .gte('month_start_date', start.toIso8601String())
          .lt('month_start_date', end.toIso8601String());

      final list = (res as List).cast<Map<String, dynamic>>();
      final months = <int>{};

      for (final row in list) {
        final value = row['month_start_date'];
        if (value == null) continue;
        final dt = DateTime.tryParse(value.toString());
        if (dt == null) continue;
        months.add(dt.month);
      }

      setState(() {
        _availableMonths = months;
      });
    } catch (e) {
      // 失敗した場合はとりあえず空にしておく
      setState(() {
        _availableMonths = {};
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
                        onPressed: () async {
                          setState(() {
                            _selectedYear = _yearOptions[tempIndex];
                          });
                          Navigator.pop(context);
                          await _loadAvailableMonths();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 上部：タイトル + 年のドロップダウン + 週の本棚へボタン
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.menu_book,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '本棚',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _yearOptions.isEmpty
                      ? null
                      : () => _showYearPicker(context),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.7),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedYear != null
                                ? '${_selectedYear!} 年'
                                : '年を選択',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WeeklyLibraryPage(),
                      ),
                    );
                  },
                  child: const Text('週の本棚へ'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 下部：本棚イメージ表示に変更
          Expanded(
            child: BookShelfView(
              year: _selectedYear ?? DateTime.now().year,
              availableMonths: _availableMonths,
            ),
          ),
        ],
      ),
    );
  }
}

class BookShelfView extends StatelessWidget {
  const BookShelfView({
    super.key,
    required this.year,
    required this.availableMonths,
  });

  final int year;
  final Set<int> availableMonths;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 本棚画像のアスペクト比（元画像 1022x957 から算出）
        const shelfAspectRatio = 1022 / 957;

        final shelfWidth = constraints.maxWidth;
        final shelfHeight = shelfWidth / shelfAspectRatio;

        // 棚の上に本を置くための相対位置（後で微調整可能）
        const rowYFactors = [0.24, 0.55, 0.88]; // 1段目〜3段目の縦位置
        const colXFactors = [0.15, 0.38, 0.63, 0.86]; // 左から1〜4列目の横位置

        // 本の幅（棚全体の幅に対する割合）
        final bookWidth = shelfWidth * 0.17;
        final bookHeight = bookWidth * 1.5;

        const monthColors = [
          Color(0xFFE8F0FF), // 1月
          Color(0xFFC62828), // 2月
          Color(0xFFF48FB1), // 3月
          Color(0xFFA5D6A7), // 4月
          Color(0xFF43A047), // 5月
          Color(0xFF9575CD), // 6月
          Color(0xFF42A5F5), // 7月
          Color(0xFFFFB74D), // 8月
          Color(0xFF8D6E63), // 9月
          Color(0xFF6A1B9A), // 10月
          Color(0xFFFB8C00), // 11月
          Color(0xFFD32F2F), // 12月
        ];

        return Center(
          child: SizedBox(
            width: shelfWidth,
            height: shelfHeight,
            child: Stack(
              children: [
                // 本棚画像を土台として全体にフィット
                Positioned.fill(
                  child: Image.asset(
                    'assets/book_shelf.png',
                    fit: BoxFit.fill,
                  ),
                ),

                ...List.generate(12, (index) {
                  final month = index + 1;
                  if (!availableMonths.contains(month)) {
                    final row = index ~/ 4; // 0,1,2
                    final col = index % 4;  // 0,1,2,3

                    final left = colXFactors[col] * shelfWidth - bookWidth / 2;
                    final top = rowYFactors[row] * shelfHeight - bookHeight / 2;

                    return Positioned(
                      left: left,
                      top: top,
                      child: SizedBox(
                        width: bookWidth,
                        height: bookHeight,
                        child: Center(
                          child: Text(
                            '$month 月',
                            style: TextStyle(
                              fontSize: bookWidth * 0.32,
                              fontWeight: FontWeight.bold,
                              color: Colors.black.withOpacity(0.65),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    );
                  }

                  final row = index ~/ 4; // 0,1,2
                  final col = index % 4;  // 0,1,2,3

                  final left =
                      colXFactors[col] * shelfWidth - bookWidth / 2;
                  final top =
                      rowYFactors[row] * shelfHeight - bookHeight / 2;

                  final color = monthColors[index];

                  return Positioned(
                    left: left,
                    top: top,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MonthlyChapterPage(
                              year: year,
                              month: month,
                            ),
                          ),
                        );
                      },
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          color,
                          BlendMode.srcATop,
                        ),
                        child: Image.asset(
                          'assets/book_original.png', // ベースとなる1枚の本画像
                          width: bookWidth,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
