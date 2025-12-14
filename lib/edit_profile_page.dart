

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _nameController = TextEditingController();
  final _firstPersonController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('name, first_person')
          .eq('id', user.id)
          .maybeSingle();

      _nameController.text = (row?['name'] as String?) ?? '';
      _firstPersonController.text = (row?['first_person'] as String?) ?? '';
    } catch (e) {
      _error = '読み込みに失敗しました';
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('ユーザーが見つかりません');

      final name = _nameController.text.trim();
      final fp = _firstPersonController.text.trim();

      if (name.isEmpty) throw Exception('名前を入力してください');

      await Supabase.instance.client.from('profiles').update({
        'name': name,
        'first_person': fp.isEmpty ? 'わたし' : fp,
      }).eq('id', user.id);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _firstPersonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('名前・一人称')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                    ],
                    TextField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '名前（表示名）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _firstPersonController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: '一人称',
                        hintText: '例：わたし / ぼく / 俺（空欄なら「わたし」）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}