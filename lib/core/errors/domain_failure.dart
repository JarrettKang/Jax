class DomainFailure implements Exception {
  const DomainFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
