// Windows-only developer entry. Uses real Jax widgets and a new synthetic DB.
// Never calls the production database/preferences path resolver.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:jax/app.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:path/path.dart' as p;

import 'demo_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const output = String.fromEnvironment('JAX_DEMO_DB');
  final app = await createDemo(output);
  final directory = Directory(
    p.join(p.dirname(validateCapturePath(output)), 'captures'),
  );
  if (directory.existsSync()) throw StateError('Existing captures refused.');
  await directory.create();
  final boundary = GlobalKey();
  var id = 0;
  runApp(
    RepaintBoundary(
      key: boundary,
      child: JaxApp(
        repository: SqliteEventRepository(app),
        planningRepository: SqlitePlanningRepository(app),
        worldNodeRepository: SqliteWorldNodeRepository(app),
        now: () => demoNow,
        newId: () => 'demo-ui-${id++}',
      ),
    ),
  );
  try {
    for (final page in [
      (0, 'home'),
      (3, 'planning'),
      (1, 'today'),
      (5, 'record'),
    ]) {
      await Future<void>.delayed(const Duration(seconds: 3));
      NavigationRail? rail;
      void visit(Element element) {
        if (element.widget is NavigationRail) {
          rail = element.widget as NavigationRail;
        }
        element.visitChildren(visit);
      }

      visit(boundary.currentContext! as Element);
      if (rail == null) throw StateError('Desktop navigation unavailable.');
      rail!.onDestinationSelected!(page.$1);
      await Future<void>.delayed(const Duration(seconds: 3));
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1.5);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(p.join(directory.path, '${page.$2}.png'))
          .writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    }
    await app.close();
    exit(0);
  } catch (_) {
    await app.close();
    exit(1);
  }
}

// The DB has just been created; only normalize the already-validated location.
String validateCapturePath(String path) => p.normalize(p.absolute(path));
