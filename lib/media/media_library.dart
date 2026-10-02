import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

import 'media_filter.dart';

/// Acesso à galeria do aparelho via MediaStore (Android) / PhotoKit (iOS).
class MediaLibrary {
  /// No Android filtra e ordena direto no MediaStore, pela coluna `_size`, do
  /// maior pro menor. No iOS essas colunas não existem: os filtros são
  /// ignorados e cai na ordem padrão (data).
  static PMFilter _query(MediaFilter filter) => Platform.isAndroid
      ? CustomFilter.sql(
          where: filter.toSqlWhere(),
          orderBy: [OrderByItem.desc(CustomColumns.android.size)],
        )
      : FilterOptionGroup();

  final _sizes = <String, int>{};

  Future<bool> requestAccess() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: false,
        ),
      ),
    );
    return state.hasAccess;
  }

  Future<void> openSettings() => PhotoManager.openSetting();

  /// Álbuns que têm algo dentro do [filter]. O "Tudo" vem com isAll.
  Future<List<AssetPathEntity>> albums({MediaFilter filter = MediaFilter.none}) =>
      PhotoManager.getAssetPathList(
        type: filter.requestType,
        filterOption: _query(filter),
      );

  /// Ano do item mais antigo da galeria, pra montar a lista de anos.
  Future<int> oldestYear() async {
    final now = DateTime.now().year;
    if (!Platform.isAndroid) return now;
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
      filterOption: CustomFilter.sql(
        where: MediaFilter.none.toSqlWhere(),
        orderBy: [OrderByItem.asc(CustomColumns.android.createDate)],
      ),
    );
    if (paths.isEmpty) return now;
    final oldest = await paths.first.getAssetListRange(start: 0, end: 1);
    return oldest.isEmpty ? now : oldest.first.createDateTime.year;
  }

  Future<List<AssetEntity>> page(AssetPathEntity album, int page, {int size = 60}) =>
      album.getAssetListPaged(page: page, size: size);

  /// Tamanho em bytes, com cache (é uma query no MediaStore por item).
  Future<int> sizeOf(AssetEntity asset) async {
    final cached = _sizes[asset.id];
    if (cached != null) return cached;
    final size = await asset.fileSize;
    _sizes[asset.id] = size;
    return size;
  }

  /// Soma o tamanho de todos os itens do álbum, em lotes.
  /// [isCancelled] permite abandonar a conta quando a tela sai.
  Future<int> totalSize(AssetPathEntity album, {bool Function()? isCancelled}) async {
    const batch = 300;
    final count = await album.assetCountAsync;
    var total = 0;
    for (var start = 0; start < count; start += batch) {
      if (isCancelled?.call() ?? false) return total;
      final assets = await album.getAssetListRange(start: start, end: start + batch);
      final sizes = await Future.wait(assets.map(sizeOf));
      total += sizes.fold(0, (a, b) => a + b);
    }
    return total;
  }

  /// Manda pra lixeira do sistema (Android 11+ mostra o diálogo nativo,
  /// iOS manda pra "Apagados recentemente").
  ///
  /// [trashed] são os ids que saíram; vazio se o usuário cancelou.
  /// [missing] são ids que nem existem mais (apagados por fora do app).
  Future<({List<String> trashed, List<String> missing})> trash(List<String> ids) async {
    final entities = <AssetEntity>[];
    final missing = <String>[];
    for (final id in ids) {
      final entity = await AssetEntity.fromId(id);
      entity == null ? missing.add(id) : entities.add(entity);
    }
    if (entities.isEmpty) return (trashed: <String>[], missing: missing);
    final trashed = Platform.isIOS
        ? await PhotoManager.editor.deleteWithIds(entities.map((e) => e.id).toList())
        : await PhotoManager.editor.android.moveToTrash(entities);
    return (trashed: trashed, missing: missing);
  }
}
