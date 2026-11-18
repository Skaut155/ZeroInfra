import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DownloadResult {
  final int downloaded;
  final int alreadyCached;
  final int failed;

  DownloadResult({
    required this.downloaded,
    required this.alreadyCached,
    required this.failed,
  });

  bool get isSuccess => failed == 0;
}

class MapCacheService {
  static String? _cacheDirectoryPath;

  static Future<String> getCachePath() async {
    if (_cacheDirectoryPath != null) return _cacheDirectoryPath!;
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/map_tiles_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    _cacheDirectoryPath = cacheDir.path;
    return _cacheDirectoryPath!;
  }

  static int _lonToTileX(double lon, int zoom) {
    return ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  }

  static int _latToTileY(double lat, int zoom) {
    final latRad = lat * pi / 180.0;
    return ((1.0 - (log(tan(latRad) + (1.0 / cos(latRad))) / pi)) /
            2.0 *
            (1 << zoom))
        .floor();
  }

  static int _countTilesAroundLocation({
    required double centerLat,
    required double centerLon,
    required double radiusKm,
    required List<int> zoomLevels,
  }) {
    final latDelta = radiusKm / 111.0;
    final lonDelta = radiusKm / (111.0 * cos(centerLat * pi / 180.0).abs());
    final minLat = centerLat - latDelta;
    final maxLat = centerLat + latDelta;
    final minLon = centerLon - lonDelta;
    final maxLon = centerLon + lonDelta;

    var total = 0;
    for (final z in zoomLevels) {
      final minX = _lonToTileX(minLon, z);
      final maxX = _lonToTileX(maxLon, z);
      final minY = _latToTileY(maxLat, z);
      final maxY = _latToTileY(minLat, z);
      total += (maxX - minX + 1) * (maxY - minY + 1);
    }
    return total;
  }

  /// Descarga teselas verificando escritura real en disco
  static Future<DownloadResult> preDownloadRegion({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    required List<int> zoomLevels,
    void Function(int processed, int total)? onProgress,
  }) async {
    final cachePath = await getCachePath();
    final List<Map<String, int>> tilesToDownload = [];

    for (final z in zoomLevels) {
      final minX = _lonToTileX(minLon, z);
      final maxX = _lonToTileX(maxLon, z);
      final minY = _latToTileY(maxLat, z);
      final maxY = _latToTileY(minLat, z);

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          tilesToDownload.add({'z': z, 'x': x, 'y': y});
        }
      }
    }

    final totalTiles = tilesToDownload.length;
    int processedCount = 0;
    int downloadedCount = 0;
    int alreadyCachedCount = 0;
    int failedCount = 0;

    for (final tile in tilesToDownload) {
      final z = tile['z']!;
      final x = tile['x']!;
      final y = tile['y']!;

      final localFolder = Directory('$cachePath/$z/$x');
      final localFile = File('${localFolder.path}/$y.png');

      // Si ya existe en disco y tiene contenido (> 0 bytes), la damos por buena
      if (await localFile.exists() && await localFile.length() > 0) {
        alreadyCachedCount++;
      } else {
        try {
          final res = await http
              .get(
                Uri.parse('https://tile.openstreetmap.org/$z/$x/$y.png'),
                headers: {'User-Agent': 'com.pti.zeroinfra/1.0'},
              )
              .timeout(const Duration(seconds: 4));

          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            await localFolder.create(recursive: true);
            await localFile.writeAsBytes(res.bodyBytes);
            downloadedCount++;
          } else {
            failedCount++;
          }
        } catch (_) {
          // Captura SocketException (modo avion), timeouts y caidas de conexion
          failedCount++;
        }
      }

      processedCount++;
      if (onProgress != null) {
        onProgress(processedCount, totalTiles);
      }

      // Si las primeras 5 fallan consecutivamente y no habia nada en cache, abortamos
      if (failedCount >= 5 && downloadedCount == 0 && alreadyCachedCount == 0) {
        return DownloadResult(
          downloaded: downloadedCount,
          alreadyCached: alreadyCachedCount,
          failed: totalTiles - processedCount + failedCount,
        );
      }
    }

    return DownloadResult(
      downloaded: downloadedCount,
      alreadyCached: alreadyCachedCount,
      failed: failedCount,
    );
  }

  /// Descarga teselas en un radio alrededor de una coordenada.
  static Future<DownloadResult> preDownloadAroundLocation({
    required double centerLat,
    required double centerLon,
    double radiusKm = 1.5,
    List<int> zoomLevels = const [14, 15, 16, 17],
    void Function(int processed, int total)? onProgress,
  }) async {
    if (radiusKm <= 0) {
      throw ArgumentError.value(
        radiusKm,
        'radiusKm',
        'Debe ser mayor que cero.',
      );
    }

    final latDelta = radiusKm / 111.0;
    final longitudeScale = 111.0 * cos(centerLat * pi / 180.0).abs();
    if (longitudeScale < 0.001) {
      throw ArgumentError.value(
        centerLat,
        'centerLat',
        'La latitud no permite calcular un radio longitudinal válido.',
      );
    }
    final lonDelta = radiusKm / longitudeScale;

    return preDownloadRegion(
      minLat: centerLat - latDelta,
      maxLat: centerLat + latDelta,
      minLon: centerLon - lonDelta,
      maxLon: centerLon + lonDelta,
      zoomLevels: zoomLevels,
      onProgress: onProgress,
    );
  }

  /// Descarga contexto regional y detalle táctico alrededor de una ubicación.
  static Future<DownloadResult> preDownloadPyramidalAroundLocation({
    required double centerLat,
    required double centerLon,
    double tacticalRadiusKm = 1.5,
    double regionalRadiusKm = 20.0,
    void Function(int processed, int total)? onProgress,
  }) async {
    const regionalZooms = [11, 12, 13];
    const tacticalZooms = [14, 15, 16, 17];
    final regionalTotal = _countTilesAroundLocation(
      centerLat: centerLat,
      centerLon: centerLon,
      radiusKm: regionalRadiusKm,
      zoomLevels: regionalZooms,
    );
    final tacticalTotal = _countTilesAroundLocation(
      centerLat: centerLat,
      centerLon: centerLon,
      radiusKm: tacticalRadiusKm,
      zoomLevels: tacticalZooms,
    );
    final total = regionalTotal + tacticalTotal;

    final regionalResult = await preDownloadAroundLocation(
      centerLat: centerLat,
      centerLon: centerLon,
      radiusKm: regionalRadiusKm,
      zoomLevels: regionalZooms,
      onProgress: (processed, _) => onProgress?.call(processed, total),
    );
    final tacticalResult = await preDownloadAroundLocation(
      centerLat: centerLat,
      centerLon: centerLon,
      radiusKm: tacticalRadiusKm,
      zoomLevels: tacticalZooms,
      onProgress: (processed, _) =>
          onProgress?.call(regionalTotal + processed, total),
    );

    return DownloadResult(
      downloaded: regionalResult.downloaded + tacticalResult.downloaded,
      alreadyCached:
          regionalResult.alreadyCached + tacticalResult.alreadyCached,
      failed: regionalResult.failed + tacticalResult.failed,
    );
  }

  /// Elimina todas las teselas almacenadas en el almacenamiento interno.
  static Future<void> clearCache() async {
    final cacheDir = Directory(await getCachePath());
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
    await cacheDir.create(recursive: true);
  }

  /// Calcula el espacio ocupado por la caché de mapas en megabytes.
  static Future<double> getCacheSizeMB() async {
    final cacheDir = Directory(await getCachePath());
    if (!await cacheDir.exists()) {
      return 0;
    }

    var totalBytes = 0;
    await for (final entity in cacheDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        totalBytes += await entity.length();
      }
    }
    return totalBytes / (1024 * 1024);
  }
}
