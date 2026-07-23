import 'dart:async';

/// Debounced merge of Explorer / Share path handoffs before the peer picker.
class PendingSendQueue {
  PendingSendQueue({required this.onReady});

  final void Function() onReady;

  List<String> paths = const [];
  Timer? _debounce;

  void queue(List<String> incoming) {
    if (incoming.isEmpty) return;
    paths = <String>{...paths, ...incoming}.toList();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), onReady);
  }

  void clear() {
    _debounce?.cancel();
    _debounce = null;
    paths = const [];
  }

  void dispose() {
    _debounce?.cancel();
    _debounce = null;
  }
}
