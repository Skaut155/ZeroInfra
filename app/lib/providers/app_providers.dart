import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../data/ble/ble_mesh_transport.dart';
import '../data/fake/fake_mesh_repository.dart';
import '../data/mesh_repository.dart';
import '../data/meshtastic/meshtastic_client.dart';
import 'chat_provider.dart';
import 'connection_provider.dart';
import 'nodes_provider.dart';
import 'sos_provider.dart';

/// flutter run --dart-define=FAKE_MESH=true  → malla simulada, sin placa.
const bool kUseFakeMesh = bool.fromEnvironment('FAKE_MESH');

/// Repositorio de la app: [FakeMeshRepository] con `FAKE_MESH=true` y, si
/// no, [MeshtasticClient] sobre Bluetooth real.
MeshRepository createMeshRepository() => kUseFakeMesh
    ? FakeMeshRepository()
    : MeshtasticClient(BleMeshTransport());

/// Registra el [MeshRepository] y los cuatro providers por encima de [child].
///
/// Envuelve la app en `main.dart`; las vistas solo tienen que leerlos con
/// `context.watch` / `context.read`.
class AppProviders extends StatelessWidget {
  const AppProviders({super.key, required this.child, this.repository});

  final Widget child;
  /// Solo para tests: sustituye al repositorio por defecto.
  final MeshRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<MeshRepository>(
          create: (_) => repository ?? createMeshRepository(),
          dispose: (_, repo) => unawaited(repo.dispose()),
        ),
        // lazy: false → escuchan desde el arranque; si se crearan al abrir
        // su pestaña se perderían los mensajes llegados antes.
        ChangeNotifierProvider(
          create: (c) => ConnectionProvider(c.read<MeshRepository>()),
          lazy: false,
        ),
        ChangeNotifierProvider(
          create: (c) => NodesProvider(c.read<MeshRepository>()),
          lazy: false,
        ),
        ChangeNotifierProvider(
          create: (c) => ChatProvider(c.read<MeshRepository>()),
          lazy: false,
        ),
        ChangeNotifierProvider(
          create: (c) => SosProvider(c.read<MeshRepository>()),
          lazy: false,
        ),
      ],
      child: child,
    );
  }
}
