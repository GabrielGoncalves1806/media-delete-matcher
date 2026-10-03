import 'package:flutter/material.dart';

import '../format.dart';
import '../media/media_filter.dart';
import '../media/media_library.dart';
import '../media/native_bridge.dart';
import '../theme.dart';

// Peças compartilhadas entre a home (armazenamento interno) e a tela do
// cartão SD: filtros, botão "Tudo", linha de pasta, card de volume.

/// Lista de anos do filtro, do atual até o do arquivo mais antigo.
/// Devolve o filtro novo, ou null se fechou sem escolher.
Future<MediaFilter?> pickYear(BuildContext context, MediaFilter filter, int oldestYear) async {
  final years = [for (var y = DateTime.now().year; y >= oldestYear; y--) y];
  final picked = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: const Text('Todos os anos'),
            trailing: filter.year == null ? const Icon(Icons.check_rounded) : null,
            onTap: () => Navigator.pop(context, -1),
          ),
          for (final y in years)
            ListTile(
              title: Text('$y'),
              trailing: filter.year == y ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(context, y),
            ),
        ],
      ),
    ),
  );
  if (picked == null) return null;
  return filter.copyWith(year: () => picked == -1 ? null : picked);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// Card compacto de um cartão SD: mídia, outros arquivos, lixeira e livre.
class VolumeCard extends StatelessWidget {
  const VolumeCard({super.key, required this.volume, required this.library, this.onTap, this.pending});

  final StorageVolume volume;
  final MediaLibrary library;

  /// Com isso o card vira um botão ("Abrir ›").
  final VoidCallback? onTap;

  /// Quantos itens ainda pra revisar nesse volume (mostrado no canto).
  final int? pending;

  @override
  Widget build(BuildContext context) {
    final media = library.filesIn(volume.path).fold(0, (sum, f) => sum + f.size);
    final other = library.otherBytesIn(volume.path);
    final trash = library.trash.bytesIn(volume.path);
    final used = volume.total - volume.free;
    final rest = (used - media - other - trash).clamp(0, used);
    final segments = [
      (label: 'Mídias', bytes: media, color: AppColors.accent),
      (label: 'Outros arquivos', bytes: other, color: AppColors.sky),
      if (trash > 0) (label: 'Lixeira do app', bytes: trash, color: AppColors.delete),
      if (rest > 0) (label: 'Sistema de arquivos', bytes: rest, color: AppColors.system),
    ];

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sd_card_rounded, color: AppColors.warn, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  volume.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(formatBytes(used), style: display(16)),
              Text(
                ' / ${formatBytes(volume.total)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          UsageBar(
            total: volume.total,
            segments: [for (final s in segments) (bytes: s.bytes, color: s.color)],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final s in segments)
                SizedBox(
                  width: 140,
                  child: LegendItem(label: s.label, bytes: s.bytes, color: s.color),
                ),
              Text(
                '${formatBytes(volume.free)} livres',
                style: const TextStyle(color: AppColors.keep, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (onTap != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.line),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    pending == null || pending == 0
                        ? 'Nada pra revisar no cartão'
                        : '${plural(pending!, 'item', 'itens')} pra revisar no cartão',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ),
                const Text('Abrir', style: TextStyle(color: AppColors.warn, fontWeight: FontWeight.w700)),
                const Icon(Icons.chevron_right_rounded, color: AppColors.warn, size: 20),
              ],
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Barra segmentada de uso: cada categoria uma cor, o resto é espaço livre.
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.total, required this.segments});

  final int total;
  final List<({int bytes, Color color})> segments;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 14,
        color: AppColors.surface2,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Row(
              children: [
                for (final s in segments)
                  if (s.bytes > 0)
                    Container(
                      // mínimo de 2px pra categoria pequena não sumir
                      width: (s.bytes / total * width).clamp(2.0, width),
                      color: s.color,
                      margin: const EdgeInsets.only(right: 1.5),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class LegendItem extends StatelessWidget {
  const LegendItem({super.key, required this.label, required this.bytes, required this.color});

  final String label;
  final int bytes;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(formatBytes(bytes), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class AllButton extends StatelessWidget {
  const AllButton({
    super.key,
    required this.subtitle,
    required this.onTap,
    this.title = 'Tudo, maiores primeiro',
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.delete, AppColors.orange]),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.local_fire_department_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: display(17, color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AllDone extends StatelessWidget {
  const AllDone({super.key, required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.keep.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.keep),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              filtered ? 'Nada pra revisar com esse filtro' : 'Tudo revisado 🎉',
              style: const TextStyle(color: AppColors.keep, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.filter, required this.onChanged, required this.onPickYear});

  final MediaFilter filter;
  final ValueChanged<MediaFilter> onChanged;
  final VoidCallback onPickYear;

  @override
  Widget build(BuildContext context) {
    Widget kind(String label, MediaKind kind) => _Chip(
          label: label,
          selected: filter.kind == kind,
          onTap: () => onChanged(filter.copyWith(kind: kind)),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          kind('Todos', MediaKind.all),
          kind('Vídeos', MediaKind.videos),
          kind('Fotos', MediaKind.photos),
          _Chip(
            label: '> 50 MB',
            selected: filter.bigOnly,
            onTap: () => onChanged(filter.copyWith(bigOnly: !filter.bigOnly)),
          ),
          _Chip(
            label: filter.year == null ? 'Ano ▾' : '${filter.year} ▾',
            selected: filter.year != null,
            onTap: onPickYear,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.text : AppColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? AppColors.text : AppColors.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.bg : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Ícone e cor pela "cara" da pasta, como os tiles coloridos do design.
({IconData icon, Color color}) _folderStyle(String? folder) {
  final p = (folder ?? '').toLowerCase();
  if (p.contains('whatsapp')) return (icon: Icons.chat_rounded, color: AppColors.keep);
  if (p.contains('/dcim/camera')) return (icon: Icons.photo_camera_rounded, color: AppColors.warn);
  if (p.contains('screenshot')) return (icon: Icons.screenshot_rounded, color: AppColors.accent);
  if (p.contains('screenrecord')) return (icon: Icons.videocam_rounded, color: AppColors.orange);
  if (p.contains('telegram')) return (icon: Icons.send_rounded, color: AppColors.sky);
  if (p.contains('instagram') || p.contains('threads')) {
    return (icon: Icons.camera_alt_outlined, color: AppColors.pink);
  }
  if (p.contains('download')) return (icon: Icons.download_rounded, color: AppColors.sky);
  if (p.contains('movies')) return (icon: Icons.movie_rounded, color: AppColors.pink);
  return (icon: Icons.folder_rounded, color: AppColors.muted);
}

class AlbumRow extends StatelessWidget {
  const AlbumRow({super.key, 
    required this.album,
    required this.fraction,
    required this.onTap,
  });

  final Album album;
  final double fraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _folderStyle(album.folder);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(style.icon, color: style.color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          album.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(formatBytes(album.bytes), style: display(15)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    plural(album.files.length, 'item', 'itens'),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: fraction.clamp(0.02, 1.0),
                      minHeight: 3,
                      color: style.color,
                      backgroundColor: AppColors.surface2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
