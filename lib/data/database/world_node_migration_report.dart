import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/entities/world_node_ids.dart';

class LegacyWorldMigrationReport {
  const LegacyWorldMigrationReport({
    required this.legacyEvents,
    required this.worldNodes,
    required this.mapped,
    required this.missingMappings,
    required this.duplicateMappings,
    required this.deterministicIdMismatches,
    required this.hierarchyMismatches,
    required this.categoryMismatches,
    required this.orderMismatches,
    required this.statusMappingMismatches,
  });

  final int legacyEvents;
  final int worldNodes;
  final int mapped;
  final int missingMappings;
  final int duplicateMappings;
  final int deterministicIdMismatches;
  final int hierarchyMismatches;
  final int categoryMismatches;
  final int orderMismatches;
  final int statusMappingMismatches;

  bool get isExactMigration =>
      legacyEvents == worldNodes &&
      legacyEvents == mapped &&
      missingMappings == 0 &&
      duplicateMappings == 0 &&
      deterministicIdMismatches == 0 &&
      hierarchyMismatches == 0 &&
      categoryMismatches == 0 &&
      orderMismatches == 0 &&
      statusMappingMismatches == 0;

  Map<String, Object?> toJson() => {
    'legacyEvents': legacyEvents,
    'worldNodes': worldNodes,
    'mapped': mapped,
    'missingMappings': missingMappings,
    'duplicateMappings': duplicateMappings,
    'deterministicIdMismatches': deterministicIdMismatches,
    'hierarchyMismatches': hierarchyMismatches,
    'categoryMismatches': categoryMismatches,
    'orderMismatches': orderMismatches,
    'statusMappingMismatches': statusMappingMismatches,
    'isExactMigration': isExactMigration,
  };
}

class WorldNodeMigrationReporter {
  const WorldNodeMigrationReporter(this.database);

  final Database database;

  Future<LegacyWorldMigrationReport> inspect() async {
    final events = (await database.query('events'))
        .map(Map<String, Object?>.from)
        .toList();
    final nodes = (await database.query('world_nodes'))
        .map(Map<String, Object?>.from)
        .toList();
    final links = (await database.query('legacy_event_world_node_links'))
        .map(Map<String, Object?>.from)
        .toList();
    final nodeById = {for (final row in nodes) row['id']! as String: row};
    final linksByEvent = <String, List<Map<String, Object?>>>{};
    final linksByNode = <String, List<Map<String, Object?>>>{};
    for (final link in links) {
      linksByEvent
          .putIfAbsent(link['legacy_event_id']! as String, () => [])
          .add(link);
      linksByNode
          .putIfAbsent(link['world_node_id']! as String, () => [])
          .add(link);
    }
    final expectedOrder = _expectedOrders(events);
    var missing = 0;
    var deterministic = 0;
    var hierarchy = 0;
    var category = 0;
    var order = 0;
    var status = 0;
    for (final event in events) {
      final eventId = event['id']! as String;
      final eventLinks = linksByEvent[eventId] ?? const [];
      if (eventLinks.length != 1) {
        if (eventLinks.isEmpty) missing++;
        continue;
      }
      final expectedNodeId = WorldNodeIds.fromLegacyEvent(eventId);
      final actualNodeId = eventLinks.single['world_node_id'] as String;
      if (actualNodeId != expectedNodeId) deterministic++;
      final node = nodeById[actualNodeId];
      if (node == null) continue;
      final parentEventId = event['parent_event_id'] as String?;
      final expectedParent = parentEventId == null
          ? null
          : WorldNodeIds.fromLegacyEvent(parentEventId);
      if (node['parent_world_node_id'] != expectedParent) hierarchy++;
      final expectedCategory = parentEventId == null
          ? event['category_id']
          : null;
      if (node['category_id'] != expectedCategory) category++;
      if (node['sort_order'] != expectedOrder[eventId]) order++;
      final expectedStatus = event['status'] == 'completed'
          ? 'completed'
          : 'inProgress';
      if (node['status'] != expectedStatus) status++;
    }
    final duplicates = [
      ...linksByEvent.values,
      ...linksByNode.values,
    ].where((values) => values.length > 1).length;
    return LegacyWorldMigrationReport(
      legacyEvents: events.length,
      worldNodes: nodes.length,
      mapped: links.length,
      missingMappings: missing,
      duplicateMappings: duplicates,
      deterministicIdMismatches: deterministic,
      hierarchyMismatches: hierarchy,
      categoryMismatches: category,
      orderMismatches: order,
      statusMappingMismatches: status,
    );
  }

  Map<String, int> _expectedOrders(List<Map<String, Object?>> events) {
    final ordered = [...events]
      ..sort((left, right) {
        final leftOrder = left['sort_order'] as int?;
        final rightOrder = right['sort_order'] as int?;
        if (leftOrder != null || rightOrder != null) {
          if (leftOrder == null) return 1;
          if (rightOrder == null) return -1;
          final compared = leftOrder.compareTo(rightOrder);
          if (compared != 0) return compared;
        }
        final created = (left['created_at_utc']! as int).compareTo(
          right['created_at_utc']! as int,
        );
        return created != 0
            ? created
            : (left['id']! as String).compareTo(right['id']! as String);
      });
    final counters = <String, int>{};
    final result = <String, int>{};
    for (final event in ordered) {
      final parent = event['parent_event_id'] as String?;
      final scope = parent == null
          ? 'category:${event['category_id'] ?? 'uncategorized'}'
          : 'parent:$parent';
      result[event['id']! as String] = counters[scope] ?? 0;
      counters[scope] = (counters[scope] ?? 0) + 1;
    }
    return result;
  }
}
