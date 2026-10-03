import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/media/native_bridge.dart';
import 'package:media_swipe/screens/onboarding_screen.dart';
import 'package:media_swipe/theme.dart';

/// Celular com 127 de 128 GB usados e cartão SD.
class _FakeNative extends NativeBridge {
  @override
  Future<StorageStats> storageStats() async =>
      (total: 128000000000, free: 847000000, system: 20000000000);

  @override
  Future<List<StorageVolume>> storageVolumes() async => const [
        StorageVolume(path: '/sd', label: 'SD', removable: true, primary: false, total: 8, free: 1),
      ];
}

/// Avança quadro a quadro: a animação de troca de página só começa no quadro
/// seguinte ao toque, então um pump único com duração longa não basta. E não
/// dá pra usar pumpAndSettle porque a demonstração da carta roda em loop.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpOnboarding(
  WidgetTester tester, {
  required VoidCallback onGrant,
  bool permissionOnly = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 860));
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: Scaffold(
      body: OnboardingScreen(
        native: _FakeNative(),
        onGrant: onGrant,
        askedBefore: false,
        permissionOnly: permissionOnly,
      ),
    ),
  ));
  await settle(tester); // barra enche
}

void main() {
  testWidgets('passo 1 com os números do aparelho, e "Pular" vai pra permissão', (tester) async {
    var granted = 0;
    await pumpOnboarding(tester, onGrant: () => granted++);

    expect(find.text('Teu celular tá cheio.\nBora resolver.'), findsOneWidget);
    expect(find.textContaining('847 MB livres'), findsOneWidget);

    await tester.tap(find.text('Pular'));
    await settle(tester);

    expect(find.text('Último passo.'), findsOneWidget);
    expect(find.text('Pular'), findsNothing);
    await tester.tap(find.text('Dar acesso e começar'));
    expect(granted, 1);
  });

  testWidgets('"Próximo" passa pelos passos e mostra o cartão nas ferramentas', (tester) async {
    await pumpOnboarding(tester, onGrant: () {});

    await tester.tap(find.text('Próximo'));
    await settle(tester);
    expect(find.text('👆 Experimenta: arrasta a carta'), findsOneWidget);

    await tester.tap(find.text('Próximo'));
    await settle(tester);
    expect(find.text('Nada some sem\ntu confirmar.'), findsOneWidget);

    await tester.tap(find.text('Próximo'));
    await settle(tester);
    expect(find.text('Pro cartão'), findsOneWidget);
  });

  testWidgets('arrastar a carta pra esquerda marca e para a demonstração', (tester) async {
    await pumpOnboarding(tester, onGrant: () {});
    await tester.tap(find.text('Próximo'));
    await settle(tester);

    await tester.drag(find.text('144 MB'), const Offset(-150, 0));
    await settle(tester);

    expect(find.text('Marcado pra apagar'), findsOneWidget);
    expect(find.text('👆 Experimenta: arrasta a carta'), findsNothing);
    // arrastar a carta não pode trocar de página (o PageView disputa o gesto)
    expect(find.text('Do maior pro menor,\nno swipe.'), findsOneWidget);
  });

  testWidgets('só a permissão, pra quem já viu o onboarding', (tester) async {
    var granted = 0;
    await pumpOnboarding(tester, onGrant: () => granted++, permissionOnly: true);

    expect(find.text('Falta o acesso\naos arquivos.'), findsOneWidget);
    expect(find.text('Pular'), findsNothing);
    await tester.tap(find.text('Dar acesso e começar'));
    expect(granted, 1);
  });
}
