import 'package:core_bloc/common/k.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class ViewStatusState extends Equatable {
  const ViewStatusState();
}

final class ViewStateLoading extends ViewStatusState {
  const ViewStateLoading();

  @override
  List<Object?> get props => [];
}

final class ViewStateSuccess extends ViewStatusState {
  const ViewStateSuccess();

  @override
  List<Object?> get props => [];
}

class ViewStateFailure extends ViewStatusState {
  final int code;
  final String? message;
  final dynamic res;

  const ViewStateFailure([this.code = K.errorUnknownCode, this.message, this.res]);
  
  @override
  List<Object?> get props => [code, message, res];
}

sealed class _ViewStateEvent {}

final class ViewStateEventLoading extends _ViewStateEvent {}

final class ViewStateEventSuccess extends _ViewStateEvent {}

final class ViewStateEventFailure extends _ViewStateEvent {
  final int code;
  final String? message;
  final dynamic res;
  ViewStateEventFailure([this.code = K.errorUnknownCode, this.message, this.res]);
}

final class ViewStateBloc extends Bloc<_ViewStateEvent, ViewStatusState> {
  final _waitingForConnection = ValueNotifier(false);
  int _connectionWaits = 0;

  ValueListenable<bool> get waitingForConnection => _waitingForConnection;

  ViewStateBloc() : super(const ViewStateSuccess()) {
    on<ViewStateEventLoading>(_viewStateLoading);
    on<ViewStateEventSuccess>(_viewStateSuccess);
    on<ViewStateEventFailure>(_viewStateFailure);
  }

  Future<T> trackConnectionWait<T>(Future<T> Function() wait) async {
    _connectionWaits++;
    try {
      _waitingForConnection.value = true;
      return await wait();
    } finally {
      if (--_connectionWaits == 0 && !isClosed) {
        _waitingForConnection.value = false;
      }
    }
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    _waitingForConnection.value = false;
    await super.close();
    _waitingForConnection.dispose();
  }

  void _viewStateLoading(
      ViewStateEventLoading event,
      Emitter<ViewStatusState> emit) {
    emit(const ViewStateLoading());
  }

  void _viewStateSuccess(
      ViewStateEventSuccess event,
      Emitter<ViewStatusState> emit) {
    emit(const ViewStateSuccess());
  }

  void _viewStateFailure(
      ViewStateEventFailure event,
      Emitter<ViewStatusState> emit) {
    emit(ViewStateFailure(event.code, event.message, event.res));
  }
}
