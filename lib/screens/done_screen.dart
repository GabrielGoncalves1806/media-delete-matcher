import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';

class DoneScreen extends StatelessWidget {
  const DoneScreen({
    super.key,
    required this.freedBytes,
    required this.count,
    required this.totalFreedBytes,
  });

  final int freedBytes;
  final int count;
  final int totalFreedBytes;

  @override
  Widget build(BuildContext context) {
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
                  border: Border.all(color: AppColors.keep, width: 10),
                ),
                alignment: Alignment.center,
                child: const Text('🎉', style: TextStyle(fontSize: 44)),
              ),
              const SizedBox(height: 24),
              Text(
                formatBytes(freedBytes),
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1),
              ),
              const SizedBox(height: 8),
              const Text('liberados agora', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(child: _Stat(value: formatCount(count), label: 'na lixeira por 30 dias')),
                  const SizedBox(width: 8),
                  Expanded(child: _Stat(value: formatBytes(totalFreedBytes), label: 'liberados no total')),
                ],
              ),
              const SizedBox(height: 28),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }
}
