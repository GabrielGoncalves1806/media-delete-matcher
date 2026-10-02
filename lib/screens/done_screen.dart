import 'package:flutter/material.dart';

import '../format.dart';
import '../media/media_library.dart';
import '../theme.dart';

class DoneScreen extends StatefulWidget {
  const DoneScreen({
    super.key,
    required this.movedBytes,
    required this.count,
    required this.library,
  });

  final int movedBytes;
  final int count;
  final MediaLibrary library;

  @override
  State<DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends State<DoneScreen> {
  int? _freed;
  bool _emptying = false;

  Future<void> _emptyTrash() async {
    setState(() => _emptying = true);
    final freed = await widget.library.trash.empty();
    if (mounted) {
      setState(() {
        _emptying = false;
        _freed = freed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trashBytes = widget.library.trash.bytes;
    final freed = _freed;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: freed == null ? AppColors.accent : AppColors.keep, width: 10),
                ),
                alignment: Alignment.center,
                child: Text(freed == null ? '🗑' : '🎉', style: const TextStyle(fontSize: 44)),
              ),
              const SizedBox(height: 24),
              Text(
                formatBytes(freed ?? widget.movedBytes),
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1),
              ),
              const SizedBox(height: 8),
              Text(
                freed == null
                    ? '${plural(widget.count, 'item foi', 'itens foram')} pra lixeira'
                    : 'liberados de verdade',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 28),
              if (freed == null && trashBytes > 0) ...[
                Text(
                  'A lixeira do app tem ${formatBytes(trashBytes)}. '
                  'O espaço só volta quando ela for esvaziada.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.delete,
                      side: const BorderSide(color: AppColors.delete),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _emptying ? null : _emptyTrash,
                    child: Text(
                      _emptying ? 'Esvaziando…' : 'Esvaziar lixeira agora (${formatBytes(trashBytes)})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.keep,
                    foregroundColor: const Color(0xFF04210F),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Continuar swipando',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
