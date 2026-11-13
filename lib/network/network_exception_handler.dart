import 'dart:async';

import 'package:core_bloc/core_bloc.dart';
import 'package:dio/dio.dart';

import '../common/k.dart';
import '../l10n/core_localizations_vi.dart';

class SessionExpiredException implements Exception {}

mixin NetworkExceptionHandler {

  CoreLocalizations get _messages {
    final context = coreNavigatorKey.currentContext;
    if (context != null) return context.coreMessage;
    return CoreLocalizationsVi();
  }

  Future<Result<T>> handleRequest<T>(
      Future<Response> Function() request, [
        T Function(dynamic)? fromJson,
      ]) async {
    try {
      final response = await request();
      return _handleResponse(response, fromJson);
    } on DioException catch (e) {
      if (e.error is SessionExpiredException) throw e.error!;
      return switch (e.type) {
        DioExceptionType.connectionError => Failure(
          Result.isNotConnect,
          _messages.networkDisconnected,
          e.response?.data,
        ),
        _ => Failure(
          e.response?.statusCode ?? Result.isDueServer,
          _messages.noServerResponse,
          e.response?.data,
        ),
      };
    } on TimeoutException {
      return Failure(Result.isTimeOut, _messages.networkTimeout);
    } catch (e, stackTrace) {
      if (e is SessionExpiredException) rethrow;
      coreLog(e.toString(), stackTrace: stackTrace, error: e, name: K.nameNetwork);
      return Failure(Result.isError, _messages.serverBusy);
    }
  }

  Result<T> _handleResponse<T>(
      Response response,
      T Function(dynamic)? fromJson,
      ) => switch (response.statusCode) {
    200 when fromJson != null => Success(fromJson(response.data)),
    200 => Success(response.data as T),
    _   => Failure(
      response.statusCode ?? Result.isHttp,
      _messages.serverError,
      response.data
    ),
  };
}