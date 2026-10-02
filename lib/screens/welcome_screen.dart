import 'package:flutter/material.dart';

import '../theme.dart';

/// Primeira tela: explica o app e só então pede o acesso aos arquivos.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onGrant, required this.askedBefore});

  final VoidCallback onGrant;

  /// Já foi pra tela do sistema e voltou sem liberar.
  final bool askedBefore;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Center(child: _CardStack()),
                const SizedBox(height: 32),
                Text('Libera espaço\nno swipe', style: display(36)),
                const SizedBox(height: 12),
                const Text(
                  'Passa pelas tuas fotos e vídeos do maior pro menor. '
                  'Esquerda apaga, direita mantém.',
                  style: TextStyle(color: AppColors.muted, fontSize: 16, height: 1.4),
                ),
                const SizedBox(height: 24),
                const _Point(
                  icon: Icons.local_fire_department_rounded,
                  color: AppColors.orange,
                  title: 'Maiores primeiro',
                  text: 'Os primeiros swipes são os que mais liberam espaço.',
                ),
                const _Point(
                  icon: Icons.shield_rounded,
                  color: AppColors.keep,
                  title: 'Nada some sem tu confirmar',
                  text: 'Tudo passa pela revisão e fica 30 dias na lixeira.',
                ),
                const _Point(
                  icon: Icons.content_copy_rounded,
                  color: AppColors.accent,
                  title: 'Acha cópias idênticas',
                  text: 'O mesmo arquivo salvo duas vezes, byte a byte.',
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.folder_open_rounded, color: AppColors.sky, size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Por que acesso a todos os arquivos? ',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(
                                text: 'A galeria do Android esconde a mídia do WhatsApp e de '
                                    'outros apps, que costuma ser a maior parte do espaço. '
                                    'Nada sai do teu celular.',
                                style: TextStyle(color: AppColors.muted),
                              ),
                            ],
                          ),
                          style: TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (askedBefore)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Ainda sem acesso. Na tela que abrir, liga a chave do media_swipe e volta.',
                      style: TextStyle(color: AppColors.warn, fontSize: 13),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.text,
                      foregroundColor: AppColors.bg,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: onGrant,
                    child: const Text(
                      'Dar acesso e começar',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Abre a configuração do Android. Liga a chave e volta pra cá.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Três cartas em leque, com os carimbos do swipe: a "ilustração" do app.
class _CardStack extends StatelessWidget {
  const _CardStack();

  @override
  Widget build(BuildContext context) {
    Widget card(double angle, Offset offset, List<Color> colors, {Widget? child}) =>
        Transform.translate(
          offset: offset,
          child: Transform.rotate(
            angle: angle,
            child: Container(
              width: 130,
              height: 170,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 12)),
                ],
              ),
              child: child,
            ),
          ),
        );

    Widget stamp(String label, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, style: display(15, color: color)),
        );

    return SizedBox(
      width: 280,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          card(-0.22, const Offset(-70, 10), const [Color(0xFF3A2A6E), Color(0xFF1B1636)],
              child: Align(
                alignment: const Alignment(0, -0.6),
                child: Transform.rotate(angle: 0.2, child: stamp('APAGAR', AppColors.delete)),
              )),
          card(0.22, const Offset(70, 10), const [Color(0xFF14513A), Color(0xFF0E241C)],
              child: Align(
                alignment: const Alignment(0, -0.6),
                child: Transform.rotate(angle: -0.2, child: stamp('MANTER', AppColors.keep)),
              )),
          card(0, Offset.zero, const [AppColors.delete, AppColors.orange],
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_circle_fill_rounded, size: 42, color: Colors.white),
                    const SizedBox(height: 6),
                    Text('144 MB', style: display(20, color: Colors.white)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
