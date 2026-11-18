import 'package:core_bloc/core_bloc.dart';
import 'package:core_bloc/overlay/touch_reactive_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ignores a second touch after the snackbar closes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(navigatorKey: coreNavigatorKey, home: const Scaffold()),
    );
    successSnackBar('Saved', title: 'Success');
    await tester.pumpAndSettle();

    final surface = find.byType(TouchReactiveSurface);
    final center = tester.getCenter(surface);
    await tester.tapAt(center);
    final secondTouch = await tester.startGesture(center);
    await tester.pumpAndSettle();
    expect(surface, findsNothing);

    await secondTouch.moveBy(const Offset(20, 0));
    final moveException = tester.takeException();
    await secondTouch.up();

    expect(moveException, isNull);
    expect(tester.takeException(), isNull);
  });
}
