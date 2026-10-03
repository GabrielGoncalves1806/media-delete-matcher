import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Navega pelas pastas de um volume (o cartão SD) e escolhe onde colocar.
/// Dá pra criar pasta nova. Devolve o caminho escolhido, ou null.
class FolderPickerScreen extends StatefulWidget {
  const FolderPickerScreen({
    super.key,
    required this.root,
    required this.rootLabel,
    required this.actionLabel,
  });

  final String root;
  final String rootLabel;

  /// Texto do botão de confirmar ("Mover 3 itens pra cá").
  final String actionLabel;

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  late String _current = widget.root;
  List<String> _folders = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _list();
  }

  void _list() {
    try {
      final dirs = Directory(_current)
          .listSync(followLinks: false)
          .whereType<Directory>()
          .map((d) => d.path)
          .where((p) => !_name(p).startsWith('.') && !p.endsWith('/Android'))
          .toList()
        ..sort((a, b) => _name(a).toLowerCase().compareTo(_name(b).toLowerCase()));
      setState(() {
        _folders = dirs;
        _error = null;
      });
    } on FileSystemException catch (e) {
      setState(() {
        _folders = [];
        _error = 'Não consegui abrir essa pasta (${e.osError?.message ?? e.message})';
      });
    }
  }

  static String _name(String path) => path.substring(path.lastIndexOf('/') + 1);

  void _open(String path) {
    _current = path;
    _list();
  }

  bool get _atRoot => _current == widget.root;

  void _up() => _open(_current.substring(0, _current.lastIndexOf('/')));

  /// "Cartão SD › DCIM › Viagem"
  List<({String label, String path})> get _crumbs {
    final crumbs = [(label: widget.rootLabel, path: widget.root)];
    var path = widget.root;
    for (final part in _current.substring(widget.root.length).split('/').where((p) => p.isNotEmpty)) {
      path = '$path/$part';
      crumbs.add((label: part, path: path));
    }
    return crumbs;
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova pasta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nome da pasta'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Criar')),
        ],
      ),
    );
    controller.dispose();
    final clean = name?.trim() ?? '';
    if (clean.isEmpty || !mounted) return;
    if (clean.contains('/') || clean.startsWith('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nome inválido: sem "/" e sem começar com ponto')),
      );
      return;
    }
    final dir = Directory('$_current/$clean');
    try {
      await dir.create();
      _open(dir.path); // já entra na pasta nova
    } on FileSystemException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não consegui criar: ${e.osError?.message ?? e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up(); // voltar sobe uma pasta antes de fechar
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mover pro cartão'),
          actions: [
            IconButton(
              onPressed: _createFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              tooltip: 'Nova pasta',
            ),
          ],
        ),
        body: Column(
          children: [
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final (i, crumb) in _crumbs.indexed) ...[
                    if (i > 0) const Icon(Icons.chevron_right_rounded, color: AppColors.muted, size: 18),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: crumb.path == _current ? AppColors.text : AppColors.muted,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                      ),
                      onPressed: () => _open(crumb.path),
                      child: Text(crumb.label),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.line),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.delete)),
                      ),
                    )
                  : ListView(
                      children: [
                        if (!_atRoot)
                          ListTile(
                            leading: const Icon(Icons.arrow_upward_rounded, color: AppColors.muted),
                            title: const Text('Voltar uma pasta', style: TextStyle(color: AppColors.muted)),
                            onTap: _up,
                          ),
                        for (final folder in _folders)
                          ListTile(
                            leading: const Icon(Icons.folder_rounded, color: AppColors.warn),
                            title: Text(_name(folder)),
                            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                            onTap: () => _open(folder),
                          ),
                        if (_folders.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Nenhuma subpasta. Dá pra mover pra cá ou criar uma nova no ícone lá em cima.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.muted),
                            ),
                          ),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.warn,
                      foregroundColor: AppColors.bg,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _error != null ? null : () => Navigator.of(context).pop(_current),
                    child: Text(widget.actionLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
