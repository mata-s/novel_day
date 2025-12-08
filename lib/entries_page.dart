import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EntriesPage extends StatefulWidget {
  const EntriesPage({super.key});

  @override
  State<EntriesPage> createState() => _EntriesPageState();
}

class _EntriesPageState extends State<EntriesPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadEntries();
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
      final data = await client
          .from('entries')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final list = (data as List)
          .cast<Map<String, dynamic>>()
          .where((row) => row['title'] != null && row['body'] != null)
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            'まだ小説の記録がありません。\n\n「今日」のタブでメモを書いて、小説をつくってみてね。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEntries,
      child: ListView.builder(
        padding: const EdgeInsets.all(12.0),
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

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6.0),
            child: InkWell(
              onTap: () {
                // タップで詳細表示（シンプルなダイアログ）
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: Text(title),
                      content: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (createdAt.isNotEmpty || style != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Text(
                                  [
                                    if (createdAt.isNotEmpty) createdAt,
                                    if (style != null && style.isNotEmpty)
                                      _buildStyleLabel(style),
                                  ].join(' · '),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            if (memo.isNotEmpty) ...[
                              const Text(
                                'メモ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                memo,
                                style: const TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 12),
                            ],
                            const Text(
                              '小説',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              body,
                              style: const TextStyle(fontSize: 14, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('とじる'),
                        ),
                      ],
                    );
                  },
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (createdAt.isNotEmpty || style != null)
                      Text(
                        [
                          if (createdAt.isNotEmpty) createdAt,
                          if (style != null && style.isNotEmpty)
                            _buildStyleLabel(style),
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    if (createdAt.isNotEmpty || style != null)
                      const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (memo.isNotEmpty)
                      Text(
                        memo,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (memo.isNotEmpty) const SizedBox(height: 4),
                    Text(
                      bodyPreview,
                      style: const TextStyle(fontSize: 13, height: 1.3),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
