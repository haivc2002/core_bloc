import 'package:core_bloc/core_bloc.dart';
import 'package:flutter/material.dart';

extension ContextExtension on BuildContext {
  Size              get vSize               => MediaQuery.of(this).size;
  double            get vMaxWidth           => vSize.width;
  double            get vMaxHeight          => vSize.height;

  EdgeInsets        get vPadding            => MediaQuery.of(this).padding;
  double            get vPaddingTop         => vPadding.top;
  double            get vPaddingBottom      => vPadding.bottom;
  double            get vPaddingLeft        => vPadding.left;
  double            get vPaddingRight       => vPadding.right;

  Brightness        get vPlatformBrightness => MediaQuery.of(this).platformBrightness;
  ThemeData         get vTheme              => Theme.of(this);
  CoreLocalizations get coreMessage =>
      CoreLocalizations.of(this) ??
      lookupCoreLocalizations(Localizations.maybeLocaleOf(this) ?? const Locale('vi'));
}