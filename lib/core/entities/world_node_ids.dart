import 'package:uuid/uuid.dart';

class WorldNodeIds {
  const WorldNodeIds._();

  // Fixed Jax namespace. Never change: it is part of the cross-device
  // migration contract.
  static const legacyEventNamespace = 'd2f1148c-42f1-4a40-8cb8-9c4f4ad86238';

  static String fromLegacyEvent(String legacyEventId) =>
      const Uuid().v5(legacyEventNamespace, 'jax:legacy-event:$legacyEventId');

  static bool isValid(String value) => _uuidPattern.hasMatch(value);
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
