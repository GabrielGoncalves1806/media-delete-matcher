import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../media/native_bridge.dart';
import '../theme.dart';

/// Primeira abertura: 5 passos explicando o app e, no fim, o pedido de acesso
/// a todos os arquivos. Com [permissionOnly], mostra só o último passo (pra
/// quem já viu o onboarding e depois tirou a permissão).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.native,
    required this.onGrant,
    required this.askedBefore,
    this.permissionOnly = false,
  });

  final NativeBridge native;
  final VoidCallback onGrant;

  /// Já foi pra tela do sistema e voltou sem liberar.
  final bool askedBefore;
  final bool permissionOnly;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _count = 5;
  final _pages = PageController();
  int _page = 0;
  StorageStats? _storage;
  bool _hasCard = false;

  bool get _last => widget.permissionOnly || _page == _count - 1;

  @override
  void initState() {
    super.initState();
    // Espaço e volumes o Android dá sem permissão nenhuma.
    widget.native.storageStats().then((s) {
      if (mounted) setState(() => _storage = s);
    });
    widget.native.storageVolumes().then((v) {
      if (mounted) setState(() => _hasCard = v.any((volume) => volume.removable));
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int page) => _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.permissionOnly) {
      return SafeArea(
        child: Column(
          children: [
            Expanded(child: _PermissionPage(askedBefore: widget.askedBefore, standalone: true)),
            _Footer(page: 0, count: 1, last: true, onNext: widget.onGrant, onDot: (_) {}),
          ],
        ),
      );
    }

    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_page - 1); // voltar do Android volta um passo
      },
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (p) => setState(() => _page = p),
                    children: [
                      _StoragePage(storage: _storage, visible: _page == 0),
                      _SwipePage(active: _page == 1),
                      const _SafetyPage(),
                      _ToolsPage(hasCard: _hasCard),
                      _PermissionPage(askedBefore: widget.askedBefore),
                    ],
                  ),
                ),
                _Footer(
                  page: _page,
                  count: _count,
                  last: _last,
                  onNext: _last ? widget.onGrant : () => _go(_page + 1),
                  onDot: _go,
                ),
              ],
            ),
            if (!_last)
              Positioned(
                top: 4,
                right: 8,
                child: TextButton(
                  onPressed: () => _go(_count - 1),
                  style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                  child: const Text('Pular'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Layout comum: ilustração em cima, título e texto embaixo.
class _Page extends StatelessWidget {
  const _Page({required this.art, required this.title, required this.text});

  final Widget art;
  final String title;
  final InlineSpan text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Center(child: art)),
          const SizedBox(height: 20),
          Text(title, style: display(28)),
          const SizedBox(height: 10),
          Text.rich(text, style: const TextStyle(color: AppColors.muted, fontSize: 15, height: 1.45)),
        ],
      ),
    );
  }
}

const _bold = TextStyle(color: AppColors.text, fontWeight: FontWeight.w600);

// ---------------------------------------------------------------- passo 1

class _StoragePage extends StatelessWidget {
  const _StoragePage({required this.storage, required this.visible});

  final StorageStats? storage;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final s = storage;
    final used = s == null ? 0 : s.total - s.free;
    final fraction = s == null ? 0.0 : used / s.total;
    final low = s != null && s.free < 2 * 1000 * 1000 * 1000;

    return _Page(
      art: TweenAnimationBuilder<double>(
        // A barra enche quando o passo aparece.
        tween: Tween(begin: 0, end: visible ? fraction : 0),
        duration: const Duration(milliseconds: 1300),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: formatBytes(s == null ? 0 : (value * s.total).round()),
                    style: display(52),
                  ),
                  if (s != null)
                    TextSpan(
                      text: '  de ${formatBytes(s.total)}',
                      style: display(18, weight: FontWeight.w500, color: AppColors.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 16,
                color: low ? AppColors.delete : AppColors.warn,
                backgroundColor: AppColors.surface2,
              ),
            ),
            const SizedBox(height: 14),
            if (s != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (low ? AppColors.delete : AppColors.keep).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  low ? '⚠ só ${formatBytes(s.free)} livres' : '${formatBytes(s.free)} livres',
                  style: TextStyle(
                    color: low ? AppColors.delete : AppColors.keep,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
      title: low ? 'Teu celular tá cheio.\nBora resolver.' : 'Vamos ver o que\ntá ocupando espaço.',
      text: const TextSpan(
        children: [
          TextSpan(text: 'A maior parte do espaço costuma ser '),
          TextSpan(text: 'foto e vídeo', style: _bold),
          TextSpan(text: ', muito escondido em pastas que a galeria nem mostra.'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- passo 2

class _SwipePage extends StatelessWidget {
  const _SwipePage({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return _Page(
      art: _SwipeDemo(active: active),
      title: 'Do maior pro menor,\nno swipe.',
      text: const TextSpan(
        children: [
          TextSpan(text: 'Swipe', style: _bold),
          TextSpan(text: ' é arrastar a carta com o dedo, como no Tinder: '),
          TextSpan(text: 'esquerda', style: _bold),
          TextSpan(text: ' marca pra apagar, '),
          TextSpan(text: 'direita', style: _bold),
          TextSpan(text: ' mantém e '),
          TextSpan(text: 'pra cima', style: _bold),
          TextSpan(text: ' deixa um vídeo grande mais leve. As maiores vêm primeiro.'),
        ],
      ),
    );
  }
}

/// Carta de demonstração. Enquanto ninguém encosta, um "dedo" arrasta ela
/// pros três lados em loop; depois do primeiro toque, a carta é da pessoa.
class _SwipeDemo extends StatefulWidget {
  const _SwipeDemo({required this.active});

  /// Só anima quando o passo tá na tela.
  final bool active;

  @override
  State<_SwipeDemo> createState() => _SwipeDemoState();
}

class _SwipeDemoState extends State<_SwipeDemo> with TickerProviderStateMixin {
  static const _cards = [
    (size: '144 MB', video: true, colors: [AppColors.delete, AppColors.orange]),
    (size: '96 MB', video: true, colors: [Color(0xFF3FB6FF), Color(0xFF3A2A9E)]),
    (size: '9 MB', video: false, colors: [AppColors.warn, Color(0xFF9E2A5A)]),
    (size: '61 MB', video: true, colors: [AppColors.keep, Color(0xFF14513A)]),
  ];
  static const _move = 70.0;
  static const _threshold = 70.0;

  /// Loop da demonstração: esquerda, direita e cima, voltando ao centro.
  late final _demo = AnimationController(vsync: this, duration: const Duration(milliseconds: 8000));
  late final Animation<Offset> _demoOffset = TweenSequence<Offset>([
    _hold(Offset.zero, 500),
    _to(Offset.zero, const Offset(-_move, 0), 550),
    _hold(const Offset(-_move, 0), 900),
    _to(const Offset(-_move, 0), Offset.zero, 550),
    _hold(Offset.zero, 400),
    _to(Offset.zero, const Offset(_move, 0), 550),
    _hold(const Offset(_move, 0), 900),
    _to(const Offset(_move, 0), Offset.zero, 550),
    _hold(Offset.zero, 400),
    _to(Offset.zero, const Offset(0, -_move), 550),
    _hold(const Offset(0, -_move), 900),
    _to(const Offset(0, -_move), Offset.zero, 550),
    _hold(Offset.zero, 1000),
  ]).animate(_demo);

  /// Saída da carta quando a pessoa solta além do limite.
  late final _fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  Tween<Offset> _flyTween = Tween(begin: Offset.zero, end: Offset.zero);

  bool _touched = false;
  Offset _drag = Offset.zero;
  int _index = 0;
  String? _toast;

  static TweenSequenceItem<Offset> _hold(Offset at, double ms) =>
      TweenSequenceItem(tween: ConstantTween(at), weight: ms);
  static TweenSequenceItem<Offset> _to(Offset from, Offset to, double ms) => TweenSequenceItem(
        tween: Tween(begin: from, end: to).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: ms,
      );

  @override
  void initState() {
    super.initState();
    _fly.addListener(() => setState(() => _drag = _flyTween.evaluate(_fly)));
    if (widget.active) _demo.repeat();
  }

  @override
  void didUpdateWidget(_SwipeDemo old) {
    super.didUpdateWidget(old);
    if (_touched) return;
    if (widget.active && !_demo.isAnimating) {
      _demo.repeat();
    } else if (!widget.active) {
      _demo
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _demo.dispose();
    _fly.dispose();
    super.dispose();
  }

  Offset get _offset => _touched ? _drag : _demoOffset.value;

  /// A carta fica dentro de um PageView, e o arrasto horizontal dele ganharia
  /// a disputa do gesto (aceita com menos movimento que o pan), trocando de
  /// página em vez de mexer a carta. O ImmediateMultiDrag pega o gesto assim
  /// que o dedo encosta na carta; fora dela, arrastar troca de página normal.
  Drag _onStart(Offset _) {
    if (!_touched) {
      _demo.stop();
      setState(() => _touched = true);
    }
    return _CardDrag(onUpdate: _onUpdate, onEnd: _onEnd);
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_fly.isAnimating) return;
    setState(() => _drag = Offset(_drag.dx + d.delta.dx, (_drag.dy + d.delta.dy).clamp(-400.0, 0.0)));
  }

  Future<void> _onEnd() async {
    if (_fly.isAnimating) return;
    final vertical = -_drag.dy > _drag.dx.abs();
    final (Offset? target, String? message) = switch (_drag) {
      _ when vertical && -_drag.dy > _threshold => (Offset(0, -420), 'Vai pra fila de compressão'),
      _ when _drag.dx < -_threshold => (Offset(-420, 30), 'Marcado pra apagar'),
      _ when _drag.dx > _threshold => (Offset(420, 30), 'Mantido'),
      _ => (null, null),
    };
    _flyTween = Tween(begin: _drag, end: target ?? Offset.zero);
    if (target != null) HapticFeedback.lightImpact();
    await _fly.forward(from: 0);
    if (!mounted) return;
    setState(() {
      if (target != null) {
        _index++;
        _toast = message;
      }
      _drag = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final card = _cards[_index % _cards.length];
    final next = _cards[(_index + 1) % _cards.length];

    return AnimatedBuilder(
      animation: _demo,
      builder: (context, _) {
        final offset = _offset;
        final vertical = -offset.dy > offset.dx.abs();
        double fade(double v) => (v / _threshold).clamp(0.0, 1.0);
        // O dedo aparece só durante a demonstração, enquanto a carta se mexe.
        final fingerOpacity = !_touched && offset != Offset.zero ? 1.0 : 0.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 180,
              height: 240,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Transform.translate(
                      offset: const Offset(0, 12),
                      child: Transform.scale(scale: 0.94, child: _DemoFace(card: next)),
                    ),
                  ),
                  Positioned.fill(
                    child: RawGestureDetector(
                      gestures: {
                        ImmediateMultiDragGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<ImmediateMultiDragGestureRecognizer>(
                          ImmediateMultiDragGestureRecognizer.new,
                          (recognizer) => recognizer.onStart = _onStart,
                        ),
                      },
                      child: Transform.translate(
                        offset: offset,
                        child: Transform.rotate(
                          angle: offset.dx / 900,
                          child: _DemoFace(
                            card: card,
                            deleteOpacity: vertical ? 0 : fade(-offset.dx),
                            keepOpacity: vertical ? 0 : fade(offset.dx),
                            upOpacity: vertical ? fade(-offset.dy) : 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // o "dedo" da demonstração
                  Positioned(
                    left: 90 - 19 + offset.dx,
                    top: 132 - 19 + offset.dy,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: fingerOpacity,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.white.withValues(alpha: 0.18), spreadRadius: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('← apaga', style: TextStyle(color: AppColors.delete, fontWeight: FontWeight.w600, fontSize: 12)),
                SizedBox(width: 16),
                Text('↑ comprime', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600, fontSize: 12)),
                SizedBox(width: 16),
                Text('mantém →', style: TextStyle(color: AppColors.keep, fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _toast ?? (_touched ? ' ' : '👆 Experimenta: arrasta a carta'),
                key: ValueKey(_toast ?? _touched),
                style: TextStyle(
                  color: _toast == null ? AppColors.muted : AppColors.text,
                  fontSize: 12,
                  fontWeight: _toast == null ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Liga o arrasto do ImmediateMultiDrag aos métodos da carta.
class _CardDrag extends Drag {
  _CardDrag({required this.onUpdate, required this.onEnd});

  final GestureDragUpdateCallback onUpdate;
  final VoidCallback onEnd;

  @override
  void update(DragUpdateDetails details) => onUpdate(details);

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() => onEnd();
}

class _DemoFace extends StatelessWidget {
  const _DemoFace({
    required this.card,
    this.deleteOpacity = 0,
    this.keepOpacity = 0,
    this.upOpacity = 0,
  });

  final ({String size, bool video, List<Color> colors}) card;
  final double deleteOpacity;
  final double keepOpacity;
  final double upOpacity;

  @override
  Widget build(BuildContext context) {
    Widget stamp(String label, Color color, double opacity, double angle) => Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: angle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 3),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(label, style: display(16, color: color)),
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: card.colors,
        ),
        boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 30, offset: Offset(0, 14))],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(7)),
              child: Text(
                card.video ? '▶ VÍDEO' : 'FOTO',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Positioned(top: 8, right: 12, child: Text(card.size, style: display(20))),
          if (card.video)
            const Center(child: Icon(Icons.play_circle_fill_rounded, size: 44, color: Colors.white70)),
          Positioned(top: 46, right: 10, child: stamp('APAGAR', AppColors.delete, deleteOpacity, 0.2)),
          Positioned(top: 46, left: 10, child: stamp('MANTER', AppColors.keep, keepOpacity, -0.2)),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(child: stamp('COMPRIMIR', AppColors.accent, upOpacity, 0)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- passo 3

class _SafetyPage extends StatelessWidget {
  const _SafetyPage();

  @override
  Widget build(BuildContext context) {
    return const _Page(
      art: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Step(
            icon: Icons.grid_view_rounded,
            color: AppColors.delete,
            title: 'Revisão',
            text: 'Tudo que tu marcou, numa grade. Toca pra desmarcar.',
          ),
          _Arrow(),
          _Step(
            icon: Icons.recycling_rounded,
            color: AppColors.accent,
            title: 'Lixeira por 30 dias',
            text: 'Mudou de ideia? Restaura pro lugar original.',
          ),
          _Arrow(),
          _Step(
            icon: Icons.auto_awesome_rounded,
            color: AppColors.keep,
            title: 'Esvaziar = espaço livre',
            text: 'Só aqui o espaço volta pro celular.',
          ),
        ],
      ),
      title: 'Nada some sem\ntu confirmar.',
      text: TextSpan(
        children: [
          TextSpan(text: 'O swipe só '),
          TextSpan(text: 'marca', style: _bold),
          TextSpan(text: '. Apagar mesmo é sempre um passo separado, com volta.'),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.color, required this.title, required this.text});

  final IconData icon;
  final Color color;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: Icon(Icons.arrow_downward_rounded, color: AppColors.line, size: 18),
      );
}

// ---------------------------------------------------------------- passo 4

class _ToolsPage extends StatelessWidget {
  const _ToolsPage({required this.hasCard});

  final bool hasCard;

  @override
  Widget build(BuildContext context) {
    final tools = [
      (icon: Icons.content_copy_rounded, color: AppColors.accent, title: 'Duplicados', text: 'O mesmo arquivo salvo duas vezes.'),
      if (hasCard)
        (icon: Icons.sd_card_rounded, color: AppColors.warn, title: 'Pro cartão', text: 'Tira do celular sem apagar.'),
      (icon: Icons.search_rounded, color: AppColors.sky, title: 'Busca', text: 'Por nome, pasta ou ano, e age em lote.'),
      (icon: Icons.share_rounded, color: AppColors.keep, title: 'Compartilhar', text: 'Achou aquela foto? Manda direto.'),
    ];
    return _Page(
      // Linhas de dois que crescem com o texto (fonte do sistema maior não
      // estoura, como acontecia com proporção fixa).
      art: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tools.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _ToolTile(tool: tools[i])),
                  const SizedBox(width: 10),
                  Expanded(child: i + 1 < tools.length ? _ToolTile(tool: tools[i + 1]) : const SizedBox()),
                ],
              ),
            ),
          ],
        ],
      ),
      title: 'E mais umas\nferramentas.',
      text: const TextSpan(
        children: [
          TextSpan(text: 'Tudo na tela inicial, junto com o '),
          TextSpan(text: 'painel do armazenamento', style: _bold),
          TextSpan(text: '.'),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool});

  final ({IconData icon, Color color, String title, String text}) tool;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tool.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(tool.icon, color: tool.color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(tool.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(tool.text, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.3)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- passo 5

class _PermissionPage extends StatelessWidget {
  const _PermissionPage({required this.askedBefore, this.standalone = false});

  final bool askedBefore;

  /// Sozinha (permissão tirada depois do onboarding): título diferente.
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    return _Page(
      art: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.sky.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(Icons.folder_open_rounded, color: AppColors.sky, size: 42),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Por que acesso a todos os arquivos? ', style: _bold),
                  TextSpan(
                    text: 'A galeria do Android esconde a mídia do WhatsApp e de outros apps, '
                        'justo onde costuma estar a maior parte do espaço.',
                  ),
                ],
              ),
              style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.lock_rounded, color: AppColors.keep, size: 16),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Nada sai do teu celular. Sem internet, sem conta.',
                  style: TextStyle(color: AppColors.keep, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (askedBefore) ...[
            const SizedBox(height: 12),
            const Text(
              'Ainda sem acesso. Na tela que abrir, liga a chave do app e volta.',
              style: TextStyle(color: AppColors.warn, fontSize: 13),
            ),
          ],
        ],
      ),
      title: standalone ? 'Falta o acesso\naos arquivos.' : 'Último passo.',
      text: const TextSpan(
        children: [
          TextSpan(text: 'Na tela que abrir, '),
          TextSpan(text: 'liga a chave do app', style: _bold),
          TextSpan(text: ' e volta pra cá.'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- rodapé

class _Footer extends StatelessWidget {
  const _Footer({
    required this.page,
    required this.count,
    required this.last,
    required this.onNext,
    required this.onDot,
  });

  final int page;
  final int count;
  final bool last;
  final VoidCallback onNext;
  final ValueChanged<int> onDot;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: last ? AppColors.keep : AppColors.text,
        foregroundColor: last ? const Color(0xFF04210F) : AppColors.bg,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onNext,
      child: Text(
        last ? 'Dar acesso e começar' : 'Próximo',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    );

    final dots = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onDot(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.only(right: 6),
              width: i == page ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == page ? AppColors.text : AppColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Row(
        children: [
          // Sozinho (só a permissão), o botão ocupa a largura toda.
          if (count > 1) ...[dots, const SizedBox(width: 16)],
          if (last) Expanded(child: button) else ...[const Spacer(), button],
        ],
      ),
    );
  }
}
