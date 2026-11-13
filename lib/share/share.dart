import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A read-only public projection. Only the owning adapter can publish values.
class PublicValue<T> extends ChangeNotifier implements ValueListenable<T> {
  T? _value;
  bool _available = false;
  final _changes = StreamController<T>.broadcast(sync: true);

  @override
  T get value {
    if (!_available) {
      if (null is T) return null as T;
      throw StateError('Public state has no active owner.');
    }
    return _value as T;
  }

  Stream<T> get stream => _changes.stream;

  void publish(T value) {
    if (_available && _value == value) return;
    _value = value;
    _available = true;
    _changes.add(value);
    notifyListeners();
  }

  void disconnect() {
    final wasAvailable = _available;
    _available = false;
    _value = null;
    if (wasAvailable && null is T) {
      _changes.add(null as T);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _changes.close();
    super.dispose();
  }
}

class PublicBuilder<T> extends StatelessWidget {
  final ValueListenable<T> listenable;
  final Widget Function(BuildContext context, T value) builder;
  const PublicBuilder({
    super.key,
    required this.listenable,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<T>(
    valueListenable: listenable,
    builder: (context, value, _) => builder(context, value),
  );
}
