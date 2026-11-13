import 'dart:developer' as dev;

import 'package:core_bloc/common/k.dart';
import 'package:core_bloc/core_bloc.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void coreLog(String message,
    {String name = K.nameCore,
      StackTrace? stackTrace,
      Object? error}) {
  if(kDebugMode) {
    dev.log(message,
        name: name,
        stackTrace: stackTrace,
        error: error
    );}
}

GlobalKey<NavigatorState> coreNavigatorKey = GlobalKey<NavigatorState>();

/// Internal helper to resolve the most appropriate context for UI operations.
BuildContext get _currentContext {
  if(coreNavigatorKey.currentContext == null) {
    throw Exception("'coreNavigatorKey' has not been configured.\n"
        "```\n"
        "Widget build(BuildContext context) {\n"
        "\treturn MaterialApp(\n"
        "\t\ttitle: 'Flutter demo',\n"
        "\t\tnavigatorKey: coreNavigatorKey, // 👈Configure here,\n"
        "```");
  }
  return coreNavigatorKey.currentContext!;
}

/// Pushes a named route onto the navigator stack.
Future<T?> pushNamed<T extends Object?>(String routeName, {Object? arguments}) {
  return Navigator.pushNamed<T>(_currentContext, routeName, arguments: arguments);
}

/// Replaces the current route with a new named route.
Future<T?> pushReplacementNamed<T extends Object?, TO extends Object?>(String routeName, {TO? result, Object? arguments}) {
  return Navigator.pushReplacementNamed<T, TO>(_currentContext, routeName, result: result, arguments: arguments);
}

/// Pushes a named route and removes all previous routes until the predicate is met.
Future<T?> pushNamedAndRemoveAll<T extends Object?>(String routeName, {Object? arguments, bool Function(Route<dynamic>)? predicate}) {
  return Navigator.pushNamedAndRemoveUntil<T>(
    _currentContext,
    routeName,
    predicate ?? (route) => false,
    arguments: arguments,
  );
}

/// Pops the current route from the navigator stack.
void back<T>([T? result]) {
  if (coreNavigatorKey.currentState?.canPop() ?? false) {
    coreNavigatorKey.currentState?.pop(result);
  }
}

/// Pops all routes until the first route is reached.
void backToFirst() {
  Navigator.popUntil(_currentContext, (route) => route.isFirst);
}

/// Pops all routes until the specified route is reached.
void backToUntil(String routeName) {
  Navigator.popUntil(_currentContext, ModalRoute.withName(routeName));
}

/// Shows a custom dialog using the core's OverlayDialog widget.
Future<void> coreDialog({
  String title                = "",
  Widget body                 = const SizedBox(),
  List<ButtonAction> actions  = const [],
  bool canPop                 = true,
  bool disEnableActions       = false
}) {
  return showCupertinoDialog(
    context: _currentContext,
    builder: (_) => PopScope(
      canPop: canPop,
      child: OverlayDialog(
        body: body,
        title: title,
        actions: actions,
        disEnableActions: disEnableActions,
      ),
    ),
  );
}

/// Shows a custom bottom sheet.
Future<void> coreBottomSheet({
  Widget? body,
  String title = "",
  List<ButtonAction> actions = const [],
}) async {
  return showModalBottomSheet(
    context: _currentContext,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => OverlayBottom(
      title: title,
      body: body ?? const SizedBox(),
      actions: actions,
    ),
  );
}

final List<CupertinoDialogRoute<void>> _loadingOverlayRoutes = [];

/// Opens a global loading overlay that blocks user interaction.
Future<void> openLoadingOverlay() => _pushLoadingOverlay().closed;

/// Shows a loading overlay for the lifetime of an async operation.
Future<T> runWithLoadingOverlay<T>(Future<T> Function() action) async {
  final overlay = _pushLoadingOverlay();
  try {
    return await action();
  } finally {
    _removeLoadingOverlay(overlay.route);
  }
}

({CupertinoDialogRoute<void> route, Future<void> closed}) _pushLoadingOverlay() {
  final context = _currentContext;
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = CupertinoDialogRoute<void>(
    barrierColor: Colors.black26,
    barrierDismissible: false,
    context: context,
    builder: (context) => PopScope(
      canPop: false,
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: WidgetWait(color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
  _loadingOverlayRoutes.add(route);
  final closed = navigator.push<void>(route).whenComplete(() {
    _loadingOverlayRoutes.remove(route);
  });
  return (route: route, closed: closed);
}

bool _removeLoadingOverlay(CupertinoDialogRoute<void> route) {
  _loadingOverlayRoutes.remove(route);
  final navigator = route.navigator;
  if (navigator == null || !route.isActive) return false;
  navigator.removeRoute(route);
  return true;
}

/// Removes the most recently opened loading overlay without popping other routes.
void closeLoadingOverlay() {
  while (_loadingOverlayRoutes.isNotEmpty) {
    if (_removeLoadingOverlay(_loadingOverlayRoutes.last)) return;
  }
}

/// Displays a success notification using a SnackBar.
void successSnackBar(String message, {String? title}) =>
    _showSnackBar(message, status: _Status.success, title: title);

/// Displays an error notification using a SnackBar.
void errorSnackBar(String message, {String? title}) =>
    _showSnackBar(message, status: _Status.failure, title: title);

/// Displays a warning notification using a SnackBar.
void warningSnackBar(String message, {String? title}) =>
    _showSnackBar(message, status: _Status.warning, title: title);

void coreSnackBar(String message, {BuildContext? context}) =>
    _showSnackBar(message, status: _Status.normal, context: context);

/// Shows a default SnackBar that stays visible until the returned callback runs.
VoidCallback showPersistentSnackBar(String message, BuildContext context) {
  var visible = false;
  var dismissed = false;
  late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller;
  void closeVisible() {
    if (visible) {
      visible = false;
      controller.close();
    }
  }

  controller = _showSnackBar(
    message,
    status: _Status.normal,
    context: context,
    persist: true,
    onVisible: () {
      visible = true;
      if (dismissed) {
        WidgetsBinding.instance.addPostFrameCallback((_) => closeVisible());
      }
    },
  );
  controller.closed.then((_) => visible = false);
  return () {
    dismissed = true;
    closeVisible();
  };
}

/// Internal helper to display a custom SnackBar with status-based styling.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _showSnackBar(
  String message, {
  required _Status status,
  String? title,
  BuildContext? context,
  bool persist = false,
  VoidCallback? onVisible,
}) {
  final snackBarContext = context ?? _currentContext;
  Color color = Colors.green;
  IconData? icon = Icons.check_circle;
  Color textColor = Colors.white;

  switch (status) {
    case _Status.failure:
      color = Colors.red;
      title = title ?? snackBarContext.coreMessage.failure;
      icon = Icons.error;
      break;
    case _Status.warning:
      color = const Color(0xFFFAA134);
      title = title ?? snackBarContext.coreMessage.notification;
      icon = Icons.warning_rounded;
      break;
    case _Status.success:
      color = Colors.green;
      title = title ?? snackBarContext.coreMessage.success;
      icon = Icons.check_circle;
      break;
    case _Status.normal:
      final theme = Theme.of(snackBarContext);
      color = theme.snackBarTheme.backgroundColor ??
          theme.colorScheme.surfaceContainerHighest;
      textColor = theme.colorScheme.onSurface;
      icon = null;
      title = null;
      break;
  }

  return ScaffoldMessenger.of(snackBarContext).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 3),
      persist: persist,
      onVisible: onVisible,
      dismissDirection: persist ? DismissDirection.none : null,
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: OverlaySnackBar(
        color,
        icon,
        message,
        title,
        textColor: textColor,
        dismissOnTap: !persist,
      ),
    ),
  );
}

/// Internal enumeration for SnackBar status states.
enum _Status {
  failure,
  normal,
  warning,
  success
}
