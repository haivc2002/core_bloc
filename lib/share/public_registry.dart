import 'dart:async';

typedef PublicCleanup = Future<void> Function();

/// Factories are installed by the generated application composition root.
class PublicRegistry {
  static final _factories = <Type, PublicCleanup Function(Object)>{};

  static void register<T extends Object>(PublicCleanup Function(T) factory) {
    _factories[T] = (owner) => factory(owner as T);
  }

  static PublicCleanup? connect(Object owner) => _factories[owner.runtimeType]?.call(owner);
}
