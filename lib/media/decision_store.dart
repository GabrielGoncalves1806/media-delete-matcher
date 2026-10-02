import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guarda as decisões do swipe e persiste entre aberturas do app.
///
/// - [kept]: itens que o usuário quis manter (não aparecem de novo).
/// - [marked]: itens marcados pra apagar, ainda não confirmados.
/// - [unmarkedInReview]: desmarcados na revisão; dá pra marcar de novo
///   enquanto a revisão estiver aberta.
class DecisionStore extends ChangeNotifier {
  static const _keptKey = 'kept';
  static const _markedKey = 'marked';
  static const _freedKey = 'freedBytes';

  late final SharedPreferences _prefs;

  final _kept = <String>{};
  final _marked = <String, int>{}; // mantém a ordem de inserção
  final _unmarkedInReview = <String, int>{};
  int _freedBytes = 0;

  Map<String, int> get marked => UnmodifiableMapView(_marked);
  Map<String, int> get unmarkedInReview => UnmodifiableMapView(_unmarkedInReview);
  int get markedCount => _marked.length;
  int get markedBytes => _marked.values.fold(0, (a, b) => a + b);
  int get freedBytes => _freedBytes;

  bool isDecided(String id) => _kept.contains(id) || _marked.containsKey(id);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _kept.addAll(_prefs.getStringList(_keptKey) ?? const []);
    for (final entry in _prefs.getStringList(_markedKey) ?? const <String>[]) {
      final sep = entry.lastIndexOf(':');
      _marked[entry.substring(0, sep)] = int.parse(entry.substring(sep + 1));
    }
    _freedBytes = _prefs.getInt(_freedKey) ?? 0;
    notifyListeners();
  }

  void markForDeletion(String id, int bytes) {
    _kept.remove(id);
    _marked[id] = bytes;
    _changed();
  }

  void keep(String id) {
    _marked.remove(id);
    _kept.add(id);
    _changed();
  }

  /// Volta o item pro estado "sem decisão" (usado pelo desfazer do swipe).
  void forget(String id) {
    _kept.remove(id);
    _marked.remove(id);
    _changed();
  }

  /// Tocar numa miniatura da revisão alterna entre marcado e mantido.
  void toggleInReview(String id) {
    final bytes = _marked.remove(id);
    if (bytes != null) {
      _unmarkedInReview[id] = bytes;
      _kept.add(id);
    } else {
      final restored = _unmarkedInReview.remove(id);
      if (restored == null) return;
      _kept.remove(id);
      _marked[id] = restored;
    }
    _changed();
  }

  /// Chamado no dispose da revisão. Não notifica: o mapa só importa lá dentro,
  /// e notificar durante o desmonte da árvore dispara erro no Flutter.
  void closeReview() => _unmarkedInReview.clear();

  /// Depois da confirmação do sistema: tira da lista e soma no total liberado.
  void confirmTrashed(List<String> ids) {
    for (final id in ids) {
      final bytes = _marked.remove(id);
      if (bytes != null) _freedBytes += bytes;
    }
    _changed();
  }

  void _changed() {
    notifyListeners();
    _prefs.setStringList(_keptKey, _kept.toList());
    _prefs.setStringList(
      _markedKey,
      [for (final e in _marked.entries) '${e.key}:${e.value}'],
    );
    _prefs.setInt(_freedKey, _freedBytes);
  }
}
