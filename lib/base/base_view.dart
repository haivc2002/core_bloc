import 'package:core_bloc/base/base_bloc.dart';
import 'package:core_bloc/common/core_utils.dart';
import 'package:core_bloc/common/view_status.dart';
import 'package:core_bloc/common/context_extension.dart';
import 'package:core_bloc/common/scaffold_extension.dart';
import 'package:core_bloc/widget/widget_wait.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';
abstract class BaseView extends StatefulWidget {
  final Object? args;
  const BaseView({super.key, this.args});
}

abstract class BaseViewState<
  V extends BaseView,
  B extends BaseBloc,
  S
> extends State<V> {

  late        S state;
  late final  B bloc;
  bool _isArgsInitialized = false;
  VoidCallback? _closeConnectionSnackBar;

  /// Lấy arguments truyền vào từ widget.args hoặc từ ModalRoute (Navigator.pushNamed)
  Object? get args => widget.args ?? ModalRoute.of(context)?.settings.arguments;

  /// Lấy arguments theo kiểu dữ liệu cụ thể (type-safe)
  T? getArgs<T>() {
    final currentArgs = args;
    if (currentArgs is T) return currentArgs;
    return null;
  }

  bool get enableListenBuilderLoading   => true;
  bool get enableListenBuilderError     => true;

  bool get viewIsLoading => bloc.viewState.state is ViewStateLoading;
  bool get viewIsFailure => bloc.viewState.state is ViewStateFailure;
  bool get viewIsSuccess => bloc.viewState.state is ViewStateSuccess;

  void emitEvent(Object event) {
    if (!context.mounted) return;
    context.read<B>().add(event);
  }

  @override
  void initState() {
    super.initState();
    bloc  = context.read<B>();
    state = (bloc as BlocBase<S>).state;
    bloc.viewState.waitingForConnection.addListener(_updateConnectionSnackBar);
    _updateConnectionSnackBar();
  }

  void _updateConnectionSnackBar() {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (!mounted) return;
      if (bloc.viewState.waitingForConnection.value) {
        _closeConnectionSnackBar ??= showPersistentSnackBar(
          context.coreMessage.networkDisconnected,
          context,
        );
      } else {
        _closeConnectionSnackBar?.call();
        _closeConnectionSnackBar = null;
      }
    });
    binding.ensureVisualUpdate();
  }

  @override
  void dispose() {
    bloc.viewState.waitingForConnection.removeListener(_updateConnectionSnackBar);
    final closeSnackBar = _closeConnectionSnackBar;
    if (closeSnackBar != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => closeSnackBar());
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isArgsInitialized) {
      _isArgsInitialized = true;
      onInitArgs(args);
    }
  }

  /// Hook tự động gọi 1 lần khi màn hình đã sẵn sàng và nhận được arguments.
  /// Subclass có thể override hàm này để chuyển args thành event gửi vào BLoC.
  void onInitArgs(Object? args) {}

  Widget buildLoadingView() => const WidgetWait();

  Widget buildFailureView(ViewStateFailure error) {
    final defaultMessage = context.coreMessage.unknownError;
    return Center(child: Text(error.message ?? defaultMessage));
  }

  Widget buildSuccessView();

  @override
  @nonVirtual
  void setState(VoidCallback fn) {
    throw UnsupportedError('To ensure consistency across the codebase, '
        '`setState` should no longer be used. All state management and '
        'UI updates must be handled through BLoC.');
  }

  Widget _buildWithStatus(Widget? statusView) {
    final content = buildSuccessView();
    final body = content is Scaffold ? content.body : content;
    final bodyWithStatus = Stack(
      fit: StackFit.passthrough,
      children: [
        Visibility(
          visible: statusView == null,
          maintainState: true,
          child: body ?? const SizedBox.shrink(),
        ),
        if (statusView != null) Center(child: statusView),
      ],
    );
    if (content is Scaffold) {
      return content.copyWith(body: bodyWithStatus);
    }
    return bodyWithStatus;
  }

  @override
  @nonVirtual
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.opaque,
      child: _buildContent,
    );
  }

  Widget get _buildContent {
    return BlocBuilder<BlocBase<S>, S>(
      bloc: bloc as BlocBase<S>,
      builder: (context, blocState) {
        state = blocState;

        return BlocBuilder<ViewStateBloc, ViewStatusState>(
          bloc: bloc.viewState,
          builder: (context, viewState) {
            final statusView = switch (viewState) {
              ViewStateLoading() when enableListenBuilderLoading =>
                buildLoadingView(),
              ViewStateFailure() when enableListenBuilderError =>
                buildFailureView(viewState),
              _ => null,
            };
            return _buildWithStatus(statusView);
          },
        );
      }
    );
  }
}
