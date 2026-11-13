// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'core_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class CoreLocalizationsVi extends CoreLocalizations {
  CoreLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get unknownError => 'Đã có lỗi xảy ra!';

  @override
  String get close => 'Đóng';

  @override
  String get success => 'Thành công';

  @override
  String get failure => 'Thất bại';

  @override
  String get waiting => 'Vui lòng chờ';

  @override
  String get notification => 'Thông báo';

  @override
  String get serverError => 'Đã xảy ra lỗi từ máy chủ';

  @override
  String get serverBusy => 'Hệ thống đang bận';

  @override
  String get noServerResponse => 'Không nhận được phản hồi từ máy chủ';

  @override
  String get networkTimeout => 'Kết nối tới máy chủ bị quá hạn';

  @override
  String get networkDisconnected =>
      'Không có kết nối mạng, vui lòng kiểm tra lại!';
}
