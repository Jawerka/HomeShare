/// Ring buffer of recent hub events for the Web UI.
class EventLog {
  EventLog({this.maxEntries = 50});

  final int maxEntries;
  final List<Map<String, String>> _entries = [];

  void add(String kind, String message) {
    _entries.insert(0, {
      'kind': kind,
      'message': message,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
  }

  List<Map<String, String>> toJson() => List.unmodifiable(_entries);
}
