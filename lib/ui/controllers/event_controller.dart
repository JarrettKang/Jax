import 'package:flutter/foundation.dart';

import '../../core/entities/jax_event.dart';
import '../../core/errors/domain_failure.dart';
import '../../core/repositories/event_repository.dart';
import '../../core/use_cases/create_event.dart';

class EventController extends ChangeNotifier {
  EventController({
    required EventRepository repository,
    required IdGenerator newId,
    required Clock now,
  }) : _repository = repository,
       _createEvent = CreateEvent(
         repository: repository,
         newId: newId,
         now: now,
       );

  final EventRepository _repository;
  final CreateEvent _createEvent;
  List<JaxEvent> _events = const [];
  bool _loading = true;

  List<JaxEvent> get events => List.unmodifiable(_events);
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _events = await _repository.getIncompleteEvents();
    _loading = false;
    notifyListeners();
  }

  Future<String?> create(String name) async {
    try {
      await _createEvent(name);
      _events = await _repository.getIncompleteEvents();
      notifyListeners();
      return null;
    } on DomainFailure catch (failure) {
      return failure.message;
    }
  }
}
