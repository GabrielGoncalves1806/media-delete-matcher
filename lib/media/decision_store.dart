import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'json_file.dart';

/// Guarda as decisões do swipe (por caminho do arquivo) e persiste entre
/// aberturas do app.
///
/// - [kept]: itens que o usuário quis manter (não aparecem de novo).
/// - [marked]: itens marcados pra apagar, ainda não confirmados.
/// - [unmarkedInReview]: desmarcados na revisão; dá pra marcar de novo
///   enquanto a revisão estiver aberta.
///
/// Grava num arquivo JSON, agrupando as mudanças: swipes seguidos viram uma
/// gravação só, [saveDelay] depois do último. [flush] grava na hora (o app
/// chama ao ir pro fundo).
class DecisionStore extends ChangeNotifier {
  DecisionStore(this._file, {this.saveDelay = const Duration(milliseconds: 500)});

  final JsonFile _file;
  final Duration saveDelay;

  /// Versões anteriores guardavam tudo no shared_preferences.
  static const _legacyPrefs = ['kept', 'marked', 'hashCache', 'v2.kept', 'v2.marked', 'freedBytes'];

  final _kept = <String>{};
  final _marked = <String, int>{}; // mantém a ordem de inserção
  final _unmarkedInReview = <String, int>{};
  int _freedBytes = 0;
  Timer? _saveTimer;

  Set<String> get kept => UnmodifiableSetView(_kept);
  Map<String, int> get marked => UnmodifiableMapView(_marked);
  Map<String, int> get unmarkedInReview => UnmodifiableMapView(_unmarkedInReview);
  int get markedCount => _marked.length;
  int get markedBytes => _marked.values.fold(0, (a, b) => a + b);
  int get freedBytes => _freedBytes;

  bool isDecided(String path) => _kept.contains(path) || _marked.containsKey(path);

  Future<void> load() async {
    final data = await _file.read();
    if (data is Map<String, dynamic>) {
      _kept.addAll((data['kept'] as List? ?? const []).cast<String>());
      _marked.addAll((data['marked'] as Map? ?? const {}).cast<String, int>());
      _freedBytes = data['freed'] as int? ?? 0;
    } else {
      await _migrateFromPrefs();
    }
    notifyListeners();
  }

  /// Traz as decisões da v2 (shared_preferences) e limpa as chaves antigas.
  Future<void> _migrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _kept.addAll(prefs.getStringList('v2.kept') ?? const []);
    for (final entry in prefs.getStringList('v2.marked') ?? const <String>[]) {
      final sep = entry.lastIndexOf(':');
      _marked[entry.substring(0, sep)] = int.parse(entry.substring(sep + 1));
    }
    _freedBytes = prefs.getInt('freedBytes') ?? 0;
    for (final key in _legacyPrefs) {
      await prefs.remove(key);
    }
    await flush();
  }

  void markForDeletion(String path, int bytes) {
    _kept.remove(path);
    _marked[path] = bytes;
    _changed();
  }

  void keep(String path) {
    _marked.remove(path);
    _kept.add(path);
    _changed();
  }

  /// Volta o item pro estado "sem decisão" (desfazer do swipe, tela de mantidos).
  void forget(String path) {
    _kept.remove(path);
    _marked.remove(path);
    _changed();
  }

  void forgetAll(Iterable<String> paths) {
    for (final path in paths) {
      _kept.remove(path);
      _marked.remove(path);
    }
    _changed();
  }

  /// Tocar numa miniatura da revisão alterna entre marcado e mantido.
  void toggleInReview(String path) {
    final bytes = _marked.remove(path);
    if (bytes != null) {
      _unmarkedInReview[path] = bytes;
      _kept.add(path);
    } else {
      final restored = _unmarkedInReview.remove(path);
      if (restored == null) return;
      _kept.remove(path);
      _marked[path] = restored;
    }
    _changed();
  }

  /// Chamado no dispose da revisão. Não notifica: o mapa só importa lá dentro,
  /// e notificar durante o desmonte da árvore dispara erro no Flutter.
  void closeReview() => _unmarkedInReview.clear();

  /// Depois de ir pra lixeira: tira da lista e soma no total.
  void confirmTrashed(List<String> paths) {
    for (final path in paths) {
      final bytes = _marked.remove(path);
      if (bytes != null) _freedBytes += bytes;
    }
    _changed();
  }

  /// Grava agora, sem esperar o agrupamento.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _file.write({
      'kept': _kept.toList(),
      'marked': _marked,
      'freed': _freedBytes,
    });
  }

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, flush);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
