import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where each lib/src file may reach. A feature uses another feature only
/// through its `data/` and its `presentation/widgets/`, never its screens or
/// internals; `core/`, `design/` and `widgets/` are below every feature and
/// import none. `app/` and `admin/` compose features and may use any of them.
void main() {
  final root = Directory('lib/src').absolute.path;
  final directive = RegExp(
    r'''^(?:import|export)\s+'([^']+)';''',
    multiLine: true,
  );

  /// `features/<name>` for a feature file, else the first folder.
  String areaOf(String path) {
    final parts = path.substring(root.length + 1).split('/');
    return parts.first == 'features' ? 'features/${parts[1]}' : parts.first;
  }

  String? resolve(File source, String uri) {
    if (uri.startsWith('package:soolgyul/')) {
      return '${Directory('lib').absolute.path}/${uri.substring(17)}';
    }
    if (uri.contains(':')) return null;
    return File(
      '${source.parent.path}/$uri',
    ).absolute.uri.normalizePath().toFilePath();
  }

  test('features reach other features only through data and widgets', () {
    final broken = <String>[];
    for (final file in Directory(root).listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final from = areaOf(file.path);
      for (final match in directive.allMatches(file.readAsStringSync())) {
        final target = resolve(file, match.group(1)!);
        if (target == null || !target.startsWith(root)) continue;
        final to = areaOf(target);
        if (from == to || !to.startsWith('features/')) {
          if (const {'core', 'design', 'widgets'}.contains(from) &&
              to.startsWith('features/')) {
            broken.add('${file.path.substring(root.length + 1)} -> $to');
          }
          continue;
        }
        if (const {'app', 'admin'}.contains(from)) continue;
        final inside = target.substring('$root/$to/'.length);
        final open =
            inside.startsWith('data/') ||
            inside.startsWith('presentation/widgets/');
        if (!open || !from.startsWith('features/')) {
          broken.add(
            '${file.path.substring(root.length + 1)} -> '
            '${target.substring(root.length + 1)}',
          );
        }
      }
    }
    expect(broken, isEmpty, reason: broken.join('\n'));
  });
}
