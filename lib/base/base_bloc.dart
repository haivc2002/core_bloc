import 'dart:async';

import 'package:core_bloc/common/core_utils.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:core_bloc/share/public_registry.dart';

import '../common/network_catching.dart';
import '../common/pagination.dart';
import '../common/view_status.dart';

/// A base abstract class for BLoC that provides common error handling and logging capabilities.
abstract class BaseBloc<E, S> extends Bloc<E, S> with
    NetworkCatching,
    Pagination {
  BaseBloc(super.initialState) {
    scheduleMicrotask(() {
      if (!_publicClosing && !isClosed) {
        _publicCleanup = PublicRegistry.connect(this);
      }
    });
    onInitBloc();
  }

  PublicCleanup? _publicCleanup;
  bool _publicClosing = false;

  @override
  final ViewStateBloc viewState = ViewStateBloc();

  void onInitBloc() {
    coreLog('$runtimeType CREATE');
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    coreLog('[$runtimeType] onError: $error');
    super.onError(error, stackTrace);
  }

  @override
  void onTransition(Transition<E, S> transition) {
    super.onTransition(transition);
    coreLog('onTransition: ${transition.event.runtimeType} '
        '-> ${transition.nextState.runtimeType}');
  }

  @override
  Future<void> close() async {
    _publicClosing = true;
    await _publicCleanup?.call();
    _publicCleanup = null;
    coreLog("$runtimeType CLOSE");
    await viewState.close();
    disposePagination();
    await super.close();
  }
}
