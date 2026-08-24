import 'jax_event.dart';

class CompletedRecord {
  const CompletedRecord({required this.event, required this.duration});
  final JaxEvent event;
  final Duration duration;
}
