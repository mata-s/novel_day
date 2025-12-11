import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

/// 本棚から遷移してくる「月のまとめ」ページ。
/// 前のページから year, month が渡されている前提で、
/// entries テーブルの monthly 章 1件を取得して、
/// タイトルと本文だけをシンプルに表示する。
class MonthlyChapterPage extends StatefulWidget {
  const MonthlyChapterPage({
    super.key,
    required this.year,
    required this.month,
  });

  final int year;
  final int month;

  @override
  State<MonthlyChapterPage> createState() => _MonthlyChapterPageState();
}

class _MonthlyChapterPageState extends State<MonthlyChapterPage> {
  bool _isLoading = true;
  String? _errorMessage;
  String _title = '';
  String _body = '';

  late final PageController _pageController;
  int _currentPage = 0;
  List<String> _pages = [];
  int? _charsPerPage; // 画面幅に応じた1ページあたりの文字数
  int? _maxCharsPerColumn; // 1列あたりの最大文字数（レイアウトとページ分割を揃える）

  bool _showOverlay = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadChapter();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

List<String> _paginateText(String text, int charsPerPage) {
  // ✨ 改行を先に取ってからページ分割する
  final normalized = text.replaceAll('\r\n', '').replaceAll('\n', '').trim();

  if (normalized.isEmpty || charsPerPage <= 0) {
    return [];
  }

  final List<String> result = [];
  var start = 0;
  while (start < normalized.length) {
    final end = (start + charsPerPage < normalized.length)
        ? start + charsPerPage
        : normalized.length;
    result.add(normalized.substring(start, end));
    start = end;
  }
  return result;
}

  Future<void> _loadChapter() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'この月のまとめを表示するにはログインが必要です。';
      });
      return;
    }

    final year = widget.year;
    final month = widget.month;
    final start = DateTime(year, month, 1);
    final end = (month == 12)
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);

    try {
      final res = await client
          .from('entries')
          .select('title, body, month_start_date')
          .eq('user_id', user.id)
          .eq('chapter_type', 'monthly')
          .gte('month_start_date', start.toIso8601String())
          .lt('month_start_date', end.toIso8601String())
          .order('month_start_date', ascending: true)
          .limit(1);

      final list = (res as List).cast<Map<String, dynamic>>();

      if (list.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'この月のまとめはまだありません。';
        });
        return;
      }

      final data = list.first;
      final title = (data['title'] ?? '') as String;
      final rawBody = (data['body'] ?? '') as String;

      // entries.body は JSON 文字列 {"title": "...", "body": "..."} になっている前提で、
      // 中の body だけを本文として取り出す。
      String innerBody = rawBody;
      try {
        final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
        innerBody = (decoded['body'] ?? '') as String;
      } catch (e) {
        // JSON でなかった場合はそのまま rawBody を使う
        debugPrint('monthly_chapter_page: jsonDecode failed: $e');
      }

      // \n をきちんと改行として扱う
      innerBody = innerBody.replaceAll(r'\n', '\n');

      setState(() {
        _isLoading = false;
        _errorMessage = null;
        _title = title;      // 画面上部の「今月の物語」など
        _body = innerBody;   // 全文を保持
        _pages = [];         // ページ分割はレイアウト確定後に行う
        _currentPage = 0;
        _charsPerPage = null;
        _maxCharsPerColumn = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '読み込みに失敗しました。時間をおいて再度お試しください。';
      });
    }
  }

  void _goToPage(int index) {
    // ページ総数 = タイトルページ 1 + 本文ページ数
    final totalPages = _pages.isEmpty ? 0 : _pages.length + 1;
    if (totalPages == 0) return;
    if (index < 0 || index >= totalPages) return;

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    setState(() {
      _currentPage = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appBarTitle = _title.isNotEmpty
        ? _title
        : '${widget.year}年${widget.month}月';

    return WillPopScope(
      onWillPop: () async {
        // システムの戻る操作（Android 戻るボタン / iOS スワイプ戻り）を無効化
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              _showOverlay = !_showOverlay;
            });
          },
          child: Stack(
            children: [
              // 縦書き本文（常に表示）
              SafeArea(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : _errorMessage != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.6,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    // 本文が読み込まれていてエラーもない場合にだけページ分割を行う
                                    if (!_isLoading &&
                                        _errorMessage == null &&
                                        _body.isNotEmpty) {
                                      const textStyle = TextStyle(
                                        fontSize: 16,
                                        height: 1.6,
                                        color: Colors.black,
                                      );

                                      final width = constraints.maxWidth;

                                      // PageView 内の左右 24px パディング ＋ さらに安全マージン 24px を引いた「実効幅」
                                      const horizontalPadding = 48.0; // left + right = 24 + 24
                                      const safetyMargin = 24.0; // オーバーフロー防止用の余白
                                      final innerWidth =
                                          (width - horizontalPadding - safetyMargin).clamp(0.0, width);

                                      // 1列あたりの幅を、実際の文字幅＋余白から算出
                                      final testPainter = TextPainter(
                                        text: const TextSpan(text: '漢', style: textStyle),
                                        textDirection: TextDirection.ltr,
                                      );
                                      testPainter.layout();
                                      final charWidth = testPainter.width;
                                      final perColumnWidth = charWidth + 6; // 文字幅 + 余白

                                      // 有効幅から「何列入るか」を計算（最低 1 列）
                                      int columnsPerPage =
                                          innerWidth > 0 ? (innerWidth / perColumnWidth).floor() : 1;

                                      // あまりに少ない/多すぎると読みにくいので範囲を制限
                                      if (columnsPerPage < 4) {
                                        columnsPerPage = 4;
                                      } else if (columnsPerPage > 10) {
                                        columnsPerPage = 10;
                                      }

                                      // 念のため、ギリギリのときはさらに 1 列減らして絶対にオーバーしないようにする
                                      if (columnsPerPage > 4 &&
                                          columnsPerPage * perColumnWidth >= innerWidth) {
                                        columnsPerPage -= 1;
                                      }

                                      // ==== 縦方向の行数（1列あたりの文字数）を画面高さから算出 ====
                                      final pageHeight = constraints.maxHeight;
                                      const paddingTop = 80.0;
                                      const paddingBottom = 100.0; // 下のページ番号分の余白
                                      final availableHeight =
                                          pageHeight - paddingTop - paddingBottom;

                                      int maxCharsPerColumn =
                                          availableHeight > 0
                                              ? (availableHeight / testPainter.height).floor()
                                              : 15;

                                      if (maxCharsPerColumn < 15) {
                                        maxCharsPerColumn = 15;
                                      }

                                      final charsPerColumn = maxCharsPerColumn;
                                      final charsPerPage =
                                          charsPerColumn * columnsPerPage;

                                      if (_charsPerPage != charsPerPage ||
                                          _pages.isEmpty) {
                                        final pages =
                                            _paginateText(_body, charsPerPage);
                                        debugPrint(
                                            'monthly_chapter_page: width=$width, columnsPerPage=$columnsPerPage, charsPerPage=$charsPerPage, pages=${pages.length}');

                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          if (!mounted) return;
                                          setState(() {
                                            _charsPerPage = charsPerPage;
                                            _maxCharsPerColumn = maxCharsPerColumn;
                                            _pages = pages;
                                            if (_currentPage >= _pages.length) {
                                              _currentPage = _pages.length - 1;
                                              if (_currentPage < 0) {
                                                _currentPage = 0;
                                              }
                                            }
                                          });
                                        });
                                      }
                                    }

                                    if (_pages.isEmpty) {
                                      return const Center(
                                        child: Text(
                                          'この月のまとめはまだありません。',
                                          style: TextStyle(
                                            fontSize: 16,
                                            height: 1.6,
                                            color: Colors.black,
                                          ),
                                        ),
                                      );
                                    }

                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onHorizontalDragEnd: (details) {
                                        final velocity = details.primaryVelocity ?? 0;
                                        if (velocity > 0) {
                                          // 左から右へのスワイプでページを進める
                                          _goToPage(_currentPage + 1);
                                        } else if (velocity < 0) {
                                          // 右から左へのスワイプで前のページへ戻る
                                          _goToPage(_currentPage - 1);
                                        }
                                      },
                                      child: PageView.builder(
                                        controller: _pageController,
                                        reverse: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        // 1ページ目はタイトル専用ページ、それ以降が本文ページ
                                        itemCount: _pages.length + 1,
                                        onPageChanged: (index) {
                                          setState(() {
                                            _currentPage = index;
                                          });
                                        },
                                        itemBuilder: (context, index) {
                                          // index == 0 はタイトルだけを大きく中央に表示するページ
                                          if (index == 0) {
                                            final titleText =
                                                _title.isNotEmpty ? _title : '${widget.year}年${widget.month}月';
                                            return Padding(
                                              padding: const EdgeInsets.fromLTRB(40, 30, 40, 24),
                                              child: Center(
                                                child: VerticalTextView(
                                                  text: titleText,
                                                  style: const TextStyle(
                                                    fontSize: 22,
                                                    height: 1.8,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                              ),
                                            );
                                          }

                                          // 2ページ目以降は本文（縦書き）
                                          final pageText = _pages[index - 1];
                                          return Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                40, 30, 40, 24),
                                            child: VerticalTextView(
                                              text: pageText,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                height: 1.6,
                                                color: Colors.black,
                                              ),
                                              maxCharsPerColumn: _maxCharsPerColumn,
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                              _buildBottomBar(context),
                            ],
                          ),
              ),

              // タップで出し入れするオーバーレイ（戻るボタン＋タイトル）
              if (_showOverlay)
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    color: Colors.black54,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            appBarTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final theme = Theme.of(context);

    String text;
    if (_errorMessage != null && _errorMessage!.isNotEmpty) {
      text = _errorMessage!;
    } else if (_pages.isNotEmpty) {
      final totalPages = _pages.length + 1; // タイトルページを含めた総ページ数
      text = '${_currentPage + 1} / $totalPages';
    } else {
      text = '';
    }

    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.center,
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class VerticalTextView extends StatelessWidget {
  const VerticalTextView({
    super.key,
    required this.text,
    required this.style,
    this.maxCharsPerColumn,
  });

  final String text;
  final TextStyle style;
  final int? maxCharsPerColumn;

  @override
  Widget build(BuildContext context) {
    // 改行コードは一旦削除して、連続した文字列として扱う
    final plain = text.replaceAll('\r\n', '').replaceAll('\n', '');
    if (plain.isEmpty) return const SizedBox.shrink();

    final chars = plain.split('');

    // ====== 1文字の高さを計測 ======
    final tp = TextPainter(
      text: TextSpan(text: 'あ', style: style),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    final charHeight = tp.height;

    // ====== 画面の縦方向に何文字入るか計算 ======
    final pageHeight = MediaQuery.of(context).size.height;

    // 上下の余白（ステータスバーやページ番号などを考慮）
    const paddingTop = 80.0;
    const paddingBottom = 100.0; // 下のページ番号分の余白

    int effectiveMaxCharsPerColumn;
    if (maxCharsPerColumn != null) {
      effectiveMaxCharsPerColumn = maxCharsPerColumn!;
    } else {
      final availableHeight = pageHeight - paddingTop - paddingBottom;
      effectiveMaxCharsPerColumn =
          availableHeight > 0 ? (availableHeight / charHeight).floor() : 15;
      // 最低でも 15 行は保証
      if (effectiveMaxCharsPerColumn < 15) {
        effectiveMaxCharsPerColumn = 15;
      }
    }

    // 列の分割
    final List<List<String>> columns = [];
    int start = 0;
    while (start < chars.length) {
      final end = (start + effectiveMaxCharsPerColumn < chars.length)
          ? start + effectiveMaxCharsPerColumn
          : chars.length;
      columns.add(chars.sublist(start, end));
      start = end;
    }

    return Align(
      // 本文ブロック全体をページ内でやや中央寄せに配置する
      alignment: Alignment.topCenter,
      child: Row(
        // 右から左へ並べることで、日本語の縦書きの列の並びに近づける
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: columns.map((col) {
          return Padding(
            // 列間の余白
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: col.map((ch) => _buildVerticalChar(ch, style)).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVerticalChar(String ch, TextStyle style) {
    // 句読点（「、」「。」）：縦書きでは右下寄りになるよう 180° 回転
    if (ch == '、' || ch == '。') {
      return Transform.translate(
        offset: const Offset(0, 0),
        child: RotatedBox(
          quarterTurns: 2,
          child: Text(ch, style: style),
        ),
      );
    }

    // 開きカギ括弧（「 『）：縦書きでは上側に来るように 90° 回転
    if (ch == '「' || ch == '『') {
      return RotatedBox(
        quarterTurns: 1,
        child: Text(ch, style: style),
      );
    }

    // 閉じカギ括弧（」 』）：縦書きでは開きとのバランスで 90° 回転（こちらの向きの方が自然）
    if (ch == '」' || ch == '』') {
      return RotatedBox(
        quarterTurns: 1,
        child: Text(ch, style: style),
      );
    }

    // 長音符・ダッシュ類：縦書きでは縦に伸びる棒のイメージで 90° or 270° 回転
    if (ch == 'ー' || ch == '―') {
      return RotatedBox(
        quarterTurns: 3,
        child: Text(ch, style: style),
      );
    }

    // 二点リーダ（‥）：縦書きでは縦に並ぶように 90° 回転
    if (ch == '‥') {
      return RotatedBox(
        quarterTurns: 1,
        child: Text(ch, style: style),
      );
    }

    // 三点リーダ（…）：縦書きでは縦に並ぶように 90° 回転
    // 三点リーダ（…）：縦書きでは縦に並ぶように 90° 回転＋中央補正
if (ch == '…') {
  return Transform.translate(
    offset: const Offset(5, 0), // ← ここを調整して中央に寄せる
    child: RotatedBox(
      quarterTurns: 1,
      child: Text(ch, style: style),
    ),
  );
}

    // 小書き仮名なども含め、その他の文字はそのまま配置
    return Text(ch, style: style);
  }
}