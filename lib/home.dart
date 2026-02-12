import 'package:flutter/material.dart';
import 'package:novel_day/entries_page.dart';
import 'package:novel_day/library_page.dart';
import 'package:novel_day/today_page.dart';
import 'package:novel_day/settings_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _purchasesSynced = false;

  @override
  void initState() {
    super.initState();
    _syncProfileAndRevenueCat();
  }

  Future<void> _syncProfileAndRevenueCat() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    try {
      final profileRes = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (profileRes == null) {
        // プロフィールがまだ作成されていない場合は、ここでは何もしない
        return;
      }

      if (!_purchasesSynced) {
        await Purchases.logIn(user.id);
        _purchasesSynced = true;
      }
    } catch (e) {
      debugPrint('Failed to sync RevenueCat: $e');
    }
  }

  final List<Widget> _pages = const [
    TodayPage(),
    EntriesPage(),
    LibraryPage(),
    SettingsPage(),
  ];
@override
Widget build(BuildContext context) {
  final viewInsets = MediaQuery.of(context).viewInsets;

  return Scaffold(
    appBar: AppBar(
      title: Text(_titleForIndex(_currentIndex)),
    ),
    body: _pages[_currentIndex],
    bottomNavigationBar: viewInsets.bottom > 0
        ? Padding(
            padding: EdgeInsets.only(bottom: viewInsets.bottom),
            child: Container(
              height: 44,
              color: Colors.grey[100],
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: const Text(
                      '完了',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.today_outlined),
                selectedIcon: Icon(Icons.today),
                label: '今日',
              ),
              NavigationDestination(
                icon: Icon(Icons.view_list_outlined),
                selectedIcon: Icon(Icons.view_list),
                label: '記録',
              ),
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book),
                label: '本棚',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '設定',
              ),
            ],
          ),
  );
}

  String _titleForIndex(int index) {
    switch (index) {
      case 0:
        return 'NovelDay - 今日';
      case 1:
        return 'NovelDay - 記録';
      case 2:
        return 'NovelDay - 本棚';
      case 3:
        return 'NovelDay - 設定';
      default:
        return 'NovelDay';
    }
  }
}