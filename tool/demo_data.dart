// Developer-only, entirely fictional data. Never reads a source database.
import 'dart:io';

import 'package:jax/data/database/app_database.dart';
import 'package:path/path.dart' as p;

import 'private_tool_support.dart';

DateTime get demoNow => DateTime(2030, 4, 15, 10, 30);

/// Only a new database below `.local_private/demo` is accepted.
/// Existing files are always refused, even with an overwrite flag.
String validateDemoOutput(String output) {
  if (output.trim().isEmpty) {
    throw ArgumentError('Explicit output path required.');
  }
  final root = p.normalize(Directory.current.absolute.path);
  if (!File(p.join(root, 'pubspec.yaml')).existsSync()) {
    throw StateError('Run from the repository root.');
  }
  final target = p.normalize(p.absolute(output));
  final safe = p.join(root, '.local_private', 'demo');
  if (!p.isWithin(safe, target) || p.extension(target) != '.db') {
    throw StateError('Use a new .db inside .local_private/demo.');
  }
  for (final variable in ['APPDATA', 'LOCALAPPDATA']) {
    final base = Platform.environment[variable];
    if (base != null && p.isWithin(p.join(base, 'Jax'), target)) {
      throw StateError('Real user data directory refused.');
    }
  }
  rejectLinks(target);
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    if (FileSystemEntity.typeSync('$target$suffix', followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Existing target or SQLite sidecar refused.');
    }
  }
  return target;
}

Future<AppDatabase> createDemo(String output) async {
  final target = validateDemoOutput(output);
  await Directory(p.dirname(target)).create(recursive: true);
  // Reserve exclusively: no truncation if another process creates the target.
  await File(target).create(exclusive: true);
  final app = await AppDatabase.open(target);
  try {
    await seedDemo(app);
    return app;
  } catch (_) {
    await app.close();
    rethrow;
  }
}

Future<void> seedDemo(AppDatabase app) async {
  final stamp = demoNow.toUtc().millisecondsSinceEpoch;
  final day = '2030-04-15';
  await app.database.transaction((db) async {
    // Fresh fixture only, including when called by tests.
    if ((await db.query('categories')).isNotEmpty ||
        (await db.query('events')).isNotEmpty ||
        (await db.query('world_nodes')).isNotEmpty ||
        (await db.query('routines')).isNotEmpty) {
      throw StateError('Seed requires a fresh fixture.');
    }
    final times = {'created_at_utc': stamp, 'updated_at_utc': stamp};
    final categories = ['Work', 'Learning', 'Personal'];
    final nodes = [
      'Launch portfolio website',
      'Learn conversational Japanese',
      'Improve fitness routine',
    ];
    final titles = [
      'Draft landing page copy',
      'Review chapter 3 vocabulary',
      "Prepare next week's workout",
    ];
    for (var i = 0; i < 3; i++) {
      await db.insert('categories', {
        'id': 'demo-category-$i',
        'name': categories[i],
        'sort_order': i,
        'color_key': i,
        ...times,
      });
      await db.insert('world_nodes', {
        'id': 'demo-world-$i',
        'name': nodes[i],
        'status': 'inProgress',
        'is_focused': 1,
        'sort_order': i,
        'category_id': 'demo-category-$i',
        ...times,
      });
      await db.insert('plans', {
        'id': 'demo-plan-$i',
        'world_node_id': 'demo-world-$i',
        'title': [
          'Build a first draft',
          'Practice everyday conversation',
          'A balanced week',
        ][i],
        'status': 'current',
        'round_number': 1,
        ...times,
      });
      await db.insert('plan_items', {
        'id': 'demo-item-$i',
        'plan_id': 'demo-plan-$i',
        'title': titles[i],
        'status': 'dispatched',
        'sort_order': 0,
        ...times,
      });
      await db.insert('plan_items', {
        'id': 'demo-next-$i',
        'plan_id': 'demo-plan-$i',
        'title': [
          'Choose a simple color palette',
          'Practice ordering a meal',
          'Plan a weekend cycle ride',
        ][i],
        'status': 'next',
        'sort_order': 1,
        ...times,
      });
      await db.insert('events', {
        'id': 'demo-event-$i',
        'name': titles[i],
        'source_plan_item_id': 'demo-item-$i',
        'status': i == 0 ? 'paused' : 'pending',
        'first_started_at_utc': i == 0 ? stamp - 3600000 : null,
        ...times,
      });
      await db.insert('event_day_plans', {
        'event_id': 'demo-event-$i',
        'day_date': day,
        'order_index': i,
        ...times,
      });
    }
    await db.insert('world_nodes', {
      'id': 'demo-child',
      'name': 'Collect visual references',
      'status': 'inProgress',
      'is_focused': 0,
      'parent_world_node_id': 'demo-world-0',
      'sort_order': 0,
      ...times,
    });
    await db.insert('run_segments', {
      'id': 'demo-segment-0',
      'event_id': 'demo-event-0',
      'started_at_utc': stamp - 3600000,
      'ended_at_utc': stamp - 1800000,
      ...times,
    });
    await db.insert('events', {
      'id': 'demo-complete',
      'name': 'Organize downloads folder',
      'category_id': 'demo-category-2',
      'status': 'completed',
      'first_started_at_utc': stamp - 7200000,
      'completed_at_utc': stamp - 6000000,
      ...times,
    });
    await db.insert('run_segments', {
      'id': 'demo-segment-1',
      'event_id': 'demo-complete',
      'started_at_utc': stamp - 7200000,
      'ended_at_utc': stamp - 6000000,
      ...times,
    });
    for (var i = 0; i < 3; i++) {
      await db.insert('routines', {
        'id': 'demo-routine-$i',
        'name': ['Morning review', 'Evening walk', 'Weekly planning'][i],
        'routine_type': 'scheduled',
        'recurrence_type': 'daily',
        'weekday_mask': 0,
        'is_active': 1,
        'sort_order': i,
        'time_recommendation_enabled': 1,
        'time_recommendation_start_minute': i == 1 ? 1080 : 540,
        'time_recommendation_end_minute': i == 1 ? 1140 : 660,
        'time_recommendation_latest_end_minute': i == 1 ? 1200 : 720,
        'time_recommendation_reason': 'A small, repeatable step',
        ...times,
      });
    }
    await db.insert('routine_executions', {
      'id': 'demo-routine-done',
      'routine_id': 'demo-routine-0',
      'occurrence_date': day,
      'status': 'completed',
      'completed_at_utc': stamp - 4500000,
      ...times,
    });
    await db.insert('routine_run_segments', {
      'id': 'demo-routine-segment',
      'routine_execution_id': 'demo-routine-done',
      'started_at_utc': stamp - 5400000,
      'ended_at_utc': stamp - 4500000,
      ...times,
    });
    await db.insert('plan_review_notes', {
      'id': 'demo-review',
      'plan_id': 'demo-plan-0',
      'content': 'Keep the first version small; review the draft before adding details.',
      ...times,
    });
    await db.update('dataset_metadata', {
      'generation': 'jax-synthetic-demo-v1',
      'created_at_utc': stamp,
    });
    await db.insert('jax_day_carry_over_initializations', {
      'day_date': day,
      'initialized_at_utc': stamp,
    });
  });
  if ((await app.database.rawQuery('PRAGMA integrity_check'))
              .single
              .values
              .single !=
          'ok' ||
      (await app.database.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
    throw StateError('Fixture integrity failed.');
  }
}

Future<void> main(List<String> args) => runPrivateTool(args, (args) async {
  if (args.length != 1) {
    throw ArgumentError('One explicit new demo DB path required.');
  }
  final app = await createDemo(args.single);
  await app.close();
  stdout.writeln('Synthetic demo created; no source data read.');
});
