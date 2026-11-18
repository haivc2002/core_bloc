import 'dart:io';
import 'dart:math';

import 'package:core_bloc/common/core_scroll_controller.dart';
import 'package:core_bloc/widget/widget_appbar.dart';
import 'package:core_bloc/widget/widget_wait.dart';
import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

final defPaddingListView = EdgeInsets.all(16);

enum RefreshType {
  auto,
  android,
  ios
}

class WidgetListView extends StatelessWidget {
  final ScrollController? controller;
  final ScrollPhysics? physics;

  /// Defaults to fitting the content inside a dialog.
  final bool? shrinkWrap;

  final List<Widget>? children;
  final IndexedWidgetBuilder? itemBuilder;
  final int? itemCount;
  final EdgeInsetsGeometry? padding;
  final RefreshType refreshType;
  final Future<void> Function()? onRefresh;
  final Color? refreshColor;
  final IndexedWidgetBuilder? separatorBuilder;
  final bool enablePullWidgetAppBar;
  final PullProgressCubit? pullProgress;

  const WidgetListView._({
    super.key,
    this.controller,
    this.physics,
    this.shrinkWrap,
    this.children,
    this.itemBuilder,
    this.itemCount,
    this.onRefresh,
    this.padding,
    this.refreshType = RefreshType.auto,
    this.refreshColor,
    this.separatorBuilder,
    this.enablePullWidgetAppBar = false,
    this.pullProgress,
  });

  factory WidgetListView({
    Key? key,
    ScrollController? controller,
    ScrollPhysics? physics,
    bool? shrinkWrap,
    Color? refreshColor,
    required List<Widget> children,
    Future<void> Function()? onRefresh,
    RefreshType refreshType = RefreshType.auto,
    EdgeInsetsGeometry? padding,
    bool enablePullWidgetAppBar = false,
    PullProgressCubit? pullProgress,
  }) {
    return WidgetListView._(
      key: key,
      controller: controller,
      physics: physics,
      shrinkWrap: shrinkWrap,
      onRefresh: onRefresh,
      refreshColor: refreshColor,
      refreshType: refreshType,
      padding: padding,
      enablePullWidgetAppBar: enablePullWidgetAppBar,
      pullProgress: pullProgress,
      children: children,
    );
  }

  factory WidgetListView.builder({
    Key? key,
    ScrollController? controller,
    ScrollPhysics? physics,
    bool? shrinkWrap,
    required IndexedWidgetBuilder itemBuilder,
    required int itemCount,
    Color? refreshColor,
    EdgeInsetsGeometry? padding,
    RefreshType refreshType = RefreshType.auto,
    Future<void> Function()? onRefresh,
    bool enablePullWidgetAppBar = false,
    PullProgressCubit? pullProgress,
  }) {
    return WidgetListView._(
      key: key,
      controller: controller,
      physics: physics,
      shrinkWrap: shrinkWrap,
      onRefresh: onRefresh,
      refreshColor: refreshColor,
      itemBuilder: itemBuilder,
      refreshType: refreshType,
      itemCount: itemCount,
      padding: padding,
      enablePullWidgetAppBar: enablePullWidgetAppBar,
      pullProgress: pullProgress,
    );
  }

  factory WidgetListView.separated({
    Key? key,
    ScrollController? controller,
    ScrollPhysics? physics,
    bool? shrinkWrap,
    required IndexedWidgetBuilder itemBuilder,
    required IndexedWidgetBuilder separatorBuilder,
    required int itemCount,
    Color? refreshColor,
    EdgeInsetsGeometry? padding,
    RefreshType refreshType = RefreshType.auto,
    Future<void> Function()? onRefresh,
    bool enablePullWidgetAppBar = false,
    PullProgressCubit? pullProgress,
  }) {
    return WidgetListView._(
      key: key,
      controller: controller,
      physics: physics,
      shrinkWrap: shrinkWrap,
      onRefresh: onRefresh,
      refreshColor: refreshColor,
      itemBuilder: itemBuilder,
      separatorBuilder: separatorBuilder,
      refreshType: refreshType,
      itemCount: itemCount,
      padding: padding,
      enablePullWidgetAppBar: enablePullWidgetAppBar,
      pullProgress: pullProgress,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fitContent =
        shrinkWrap ?? (context.findAncestorWidgetOfExactType<Dialog>() != null);
    final ScrollPhysics effectivePhysics =
        physics ?? const BouncingScrollPhysics().applyTo(const AlwaysScrollableScrollPhysics());
    final EdgeInsetsGeometry defPadding = padding ?? defPaddingListView;
    final colorRefresh = refreshColor ??
        Theme.of(context).progressIndicatorTheme.color ??
        Theme.of(context).colorScheme.primary;

    final cubit = resolvePullProgressCubit(context, pullProgress);

    final Widget listView = () {
      if (itemBuilder != null && itemCount != null) {
        bool isCoreScroll = controller is CoreScrollController;
        int finalItemCount = itemCount!;
        bool showLoadMore = false;

        if (isCoreScroll) {
          final coreCtrl = controller as CoreScrollController;
          if (coreCtrl.isMoreEnable && itemCount! > 0) {
            finalItemCount += 1;
            showLoadMore = true;
          }
        }

        Widget finalItemBuilder(BuildContext context, int index) {
          if (showLoadMore && index == itemCount) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: WidgetWait(),
              ),
            );
          }
          return itemBuilder!(context, index);
        }

        if (separatorBuilder != null) {
          return ListView.separated(
            controller: controller,
            physics: effectivePhysics,
            shrinkWrap: fitContent,
            itemCount: finalItemCount,
            padding: defPadding,
            dragStartBehavior: DragStartBehavior.down,
            itemBuilder: finalItemBuilder,
            separatorBuilder: separatorBuilder!,
          );
        } else {
          return ListView.builder(
            controller: controller,
            physics: effectivePhysics,
            shrinkWrap: fitContent,
            itemCount: finalItemCount,
            padding: defPadding,
            dragStartBehavior: DragStartBehavior.down,
            itemBuilder: finalItemBuilder,
          );
        }
      } else {
        final List<Widget> safeChildren = children ?? [];
        bool isCoreScroll = controller is CoreScrollController;
        bool showLoadMore = false;

        if (isCoreScroll) {
          final coreCtrl = controller as CoreScrollController;
          if (coreCtrl.isMoreEnable && safeChildren.isNotEmpty) {
            showLoadMore = true;
          }
        }

        return ListView(
          controller: controller,
          physics: effectivePhysics,
          shrinkWrap: fitContent,
          padding: defPadding,
          dragStartBehavior: DragStartBehavior.down,
          children: [
            ...safeChildren,
            if (showLoadMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: WidgetWait(),
                ),
              ),
          ],
        );
      }
    }();

    final bool shouldTrackOverscroll = enablePullWidgetAppBar;
    Widget content = listView;

    if (onRefresh != null) {
      final TextDirection textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
      final double indicatorTop = max(0.0, defPadding.resolve(textDirection).top - 3.0);

      content = CustomRefreshIndicator(
        onRefresh: onRefresh!,
        onStateChanged: (change) {
          if (change.didChange(to: IndicatorState.armed)) {
            HapticFeedback.lightImpact();
          }
        },
        builder: (context, child, indicatorController) {
          return Stack(
            alignment: Alignment.topCenter,
            children: [
              TweenAnimationBuilder(
                duration: const Duration(milliseconds: 300),
                tween: Tween<double>(begin: 0, end: indicatorController.isLoading ? 30 : 0),
                curve: Curves.ease,
                builder: (context, value, _) {
                  final double offset = value + (indicatorController.value * 18);

                  return Transform.translate(
                    offset: Offset(0, offset),
                    child: child,
                  );
                },
              ),
              BlocBuilder<PullProgressCubit, double>(
                bloc: cubit,
                builder: (context, rawOverscroll) {
                  final indicatorOffset = rawOverscroll * 0.7;

                  return Positioned(
                    top: indicatorTop + indicatorOffset,
                    child: Offstage(
                      offstage: !(indicatorController.value > 0.0),
                      child: Opacity(
                        opacity: indicatorController.value.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: indicatorController.value.clamp(0.8, 1.0),
                          child: Center(
                            child: _progress(
                              colorRefresh,
                              (indicatorController.isDragging || indicatorController.isArmed)
                                  ? indicatorController.value.clamp(0.0, 0.99)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
        child: listView,
      );
    }

    if (!shouldTrackOverscroll) return content;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical) {
          double overscroll = 0.0;
          if (notification.metrics.pixels < 0) {
            overscroll = -notification.metrics.pixels;
          }
          if (enablePullWidgetAppBar && cubit.state != overscroll) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              cubit.update(overscroll);
            });
          }
        }
        return false;
      },
      child: content,
    );
  }

  bool get _isIosStyle => switch (refreshType) {
    RefreshType.ios => true,
    RefreshType.android => false,
    RefreshType.auto => Platform.isIOS,
  };

  Widget _progress(Color colorRefresh, double? value) => switch ((_isIosStyle, value)) {
    (false, _) => WidgetWait(color: colorRefresh, value: value),
    (true, final double v) => CupertinoActivityIndicator.partiallyRevealed(
        color: colorRefresh, radius: 14, progress: v),
    (true, null) => CupertinoActivityIndicator(color: colorRefresh, radius: 14),
  };
}
