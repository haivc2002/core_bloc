// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'core_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class CoreLocalizationsEn extends CoreLocalizations {
  CoreLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get unknownError => 'Something went wrong!';

  @override
  String get close => 'Close';

  @override
  String get success => 'Success';

  @override
  String get failure => 'Failure';

  @override
  String get waiting => 'Please wait';

  @override
  String get notification => 'Notification';

  @override
  String get serverError => 'A server error occurred';

  @override
  String get serverBusy => 'The system is busy';

  @override
  String get noServerResponse => 'No response received from the server';

  @override
  String get networkTimeout => 'Connection to the server timed out';

  @override
  String get networkDisconnected =>
      'No network connection, please check again!';
}
