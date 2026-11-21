import 'package:flutter_test/flutter_test.dart';
import 'package:zeroinfra/data/fake/fake_mesh_repository.dart';
import 'package:zeroinfra/main.dart';
import 'package:zeroinfra/providers/app_providers.dart';

void main() {
  testWidgets('la app arranca y muestra las cuatro pestañas', (tester) async {
    // Mismo árbol que main.dart, pero con la malla simulada: el test no toca
    // Bluetooth ni permisos.
    await tester.pumpWidget(
      AppProviders(
        repository: FakeMeshRepository(),
        child: const ZeroInfraApp(),
      ),
    );

    for (final label in ['Chat', 'Mapa', 'SOS', 'Nodos']) {
      expect(find.text(label), findsWidgets);
    }
  });
}
