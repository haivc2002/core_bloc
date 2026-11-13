import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core_bloc/common/view_status.dart';
import 'package:core_bloc/common/core_utils.dart';
import 'package:core_bloc/network/network_exception.dart';
import 'package:core_bloc/network/network_exception_handler.dart';

enum LoadingNetworkType { none, overlay, normal }

mixin NetworkCatching {
  ViewStateBloc get viewState;

  /// Runs an action and reports its result through callbacks or the view state.
  ///
  /// Set [enableListenError] to false to keep the normal content on failure.
  /// [onFailure] still handles failures when provided.
  ///
  /// [enableAutomaticConnectionRecovery] retries a disconnected action once
  /// when the device reports a connection. It waits until then or until the
  /// view state closes. Use it for actions safe to repeat.
  Future<void> runNetworkCatching<T>({
    required Future<Result<T>> Function() onAction,
    void Function(T data)? onSuccess,
    void Function(int code, String message, dynamic res)? onFailure,
    LoadingNetworkType loadingType = LoadingNetworkType.normal,
    bool enableListenError = true,
    bool enableAutomaticConnectionRecovery = false,
  }) async {
    if (viewState.isClosed) return;
    if (loadingType == LoadingNetworkType.normal) {
      viewState.add(ViewStateEventLoading());
    }

    Future<Result<T>> runAction() async {
      final response = await onAction();
      if (enableAutomaticConnectionRecovery &&
          response is Failure<T> &&
          response.code == Result.isNotConnect &&
          !viewState.isClosed &&
          await viewState.trackConnectionWait(_waitForConnection) &&
          !viewState.isClosed) {
        return onAction();
      }
      return response;
    }

    final Result<T> response;
    try {
      response = loadingType == LoadingNetworkType.overlay
          ? await runWithLoadingOverlay(runAction)
          : await runAction();
    } on SessionExpiredException {
      if (!viewState.isClosed && loadingType == LoadingNetworkType.normal) {
        viewState.add(
          enableListenError ? ViewStateEventFailure() : ViewStateEventSuccess(),
        );
      }
      return;
    }

    if (viewState.isClosed) return;
    switch (response) {
      case Success(value: final data):
        onSuccess?.call(data);
        if (!viewState.isClosed) viewState.add(ViewStateEventSuccess());
      case Failure(code: final code, message: final msg, res: final res):
        if (onFailure != null) onFailure(code, msg, res);
        if (viewState.isClosed) return;
        if (enableListenError && onFailure == null) {
          viewState.add(ViewStateEventFailure(code, msg, res));
        } else if (loadingType == LoadingNetworkType.normal) {
          viewState.add(ViewStateEventSuccess());
        }
    }
  }

  Future<bool> _waitForConnection() async {
    final connectivity = Connectivity();
    final ready = Completer<bool>();

    void complete(bool connected) {
      if (!ready.isCompleted) ready.complete(connected);
    }

    void check(List<ConnectivityResult> results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        complete(true);
      }
    }

    final closed = viewState.stream.listen(null, onDone: () => complete(false));
    StreamSubscription<List<ConnectivityResult>>? changes;
    try {
      changes = connectivity.onConnectivityChanged.listen(
        check,
        onError: (Object error, StackTrace stackTrace) => complete(false),
        onDone: () => complete(false),
      );
      unawaited(
        connectivity.checkConnectivity().then<void>(
          check,
          onError: (Object error, StackTrace stackTrace) => complete(false),
        ),
      );
      return await ready.future;
    } on Exception {
      return false;
    } finally {
      await closed.cancel();
      await changes?.cancel();
    }
  }
}
