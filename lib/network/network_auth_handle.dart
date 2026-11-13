import 'package:core_bloc/common/core_utils.dart';
import 'package:core_bloc/common/k.dart';
import 'package:core_bloc/network/network_auth_config.dart';
import 'package:core_bloc/network/network_dev_logger.dart';
import 'package:core_bloc/network/network_exception_handler.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class NetworkAuthHandle extends QueuedInterceptor {
  NetworkAuthHandle(
      this._dio,
      this._authConfig,
      this._timeOut,
      this._showTokenValue);

  final Dio _dio;
  final NetworkAuthConfig _authConfig;
  final Duration _timeOut;
  final bool _showTokenValue;

  bool _isError = false;
  
  @override
  Future<void> onRequest(
      RequestOptions options,
      RequestInterceptorHandler handler,
      ) async {
    if(!_requiresToken(options)) return handler.next(options);

    try {
      final canAttachToken = await _validateAuthentication();
      if(canAttachToken) await _attachAccessToken(options);
    } on FormatException {
      rethrow;
    } on SessionExpiredException {
      rethrow;
    } catch (e) {
      coreLog(
        'Error during token preprocessing in request header: $e',
        name: K.nameNetwork,
      );
    }

    handler.next(options);
  }

  Future<bool> _validateAuthentication() async {
    if(await _isRefreshTokenExpired()) {
      _triggerAuthErrorAndThrowIfNeeded();
      return false;
    }
    if(!await _isAccessTokenExpired()) return true;
    return _refreshIfPossible();
  }

  Future<bool> _isRefreshTokenExpired() {
    return _isExpiredBy(_authConfig.refreshTokenExpiresAt);
  }

  Future<bool> _isAccessTokenExpired() {
    return _isExpiredBy(_authConfig.expirationAt);
  }

  Future<bool> _isExpiredBy(Future<String?> Function()? expiresAt) async {
    if(expiresAt == null) return false;

    final value = await expiresAt();
    if(value == null || value.isEmpty) return false;

    return DateTime.now().isAfter(_parseDate(value));
  }

  Future<bool> _refreshIfPossible() async {
    if(_authConfig.endpoint == null) {
      _triggerAuthErrorAndThrowIfNeeded();
      return false;
    }

    try {
      await _onRefreshToken();
    } catch (e) {
      if(e is DioException && e.type == DioExceptionType.badResponse) {
        _triggerAuthErrorAndThrowIfNeeded();
        return false;
      }
    }

    return true;
  }

  Future<void> _attachAccessToken(RequestOptions options) async {
    final accessToken = _authConfig.accessToken;
    if(accessToken == null) return;

    final token = await accessToken();
    if(token == null || token.isEmpty) return;

    options.headers['Authorization'] = 'Bearer $token';
  }

  @override
  Future<void> onError(
      DioException err,
      ErrorInterceptorHandler handler,
      ) async {
    if(!_shouldHandleAuthError(err)) return handler.next(err);

    if(_isError || _authConfig.endpoint == null) {
      return _handleAuthenticationError(err, handler);
    }

    try {
      final token = await _getValidToken(err.requestOptions);
      return handler.resolve(await _retryRequest(err.requestOptions, token));
    } catch (e) {
      if(e is DioException && e.type == DioExceptionType.badResponse) {
        return _handleAuthenticationError(err, handler);
      }
      handler.next(err);
    }
  }

  bool _requiresToken(RequestOptions options) {
    return options.extra['withToken'] == true;
  }

  bool _shouldHandleAuthError(DioException err) {
    return _requiresToken(err.requestOptions) &&
        err.response?.statusCode == 401;
  }

  Future<String> _getValidToken(RequestOptions options) async {
    final originalToken = _extractToken(options);
    final currentToken = await _getAccessToken();
    if(_isTokenAlreadyRefreshed(originalToken, currentToken)) {
      return currentToken;
    }
    await _onRefreshToken();
    return _getAccessToken();
  }

  Future<String> _getAccessToken() async {
    return await _authConfig.accessToken?.call() ?? '';
  }

  bool _isTokenAlreadyRefreshed(String originalToken, String currentToken) {
    return currentToken.isNotEmpty && originalToken != currentToken;
  }

  String _extractToken(RequestOptions options) {
    final authorization = options.headers['Authorization']?.toString();

    return authorization?.replaceFirst(RegExp(r'^Bearer\s+'), '').trim() ?? '';
  }

  Future<Response<dynamic>> _retryRequest(
      RequestOptions options,
      String token,
      ) {
    options.headers['Authorization'] = 'Bearer $token';

    return _createDio(baseUrl: options.baseUrl).fetch(options);
  }

  Future<void> _onRefreshToken() async {
    final refreshToken = await _authConfig.refreshToken?.call() ?? '';
    final body = _authConfig.buildRequestBody?.call(refreshToken);

    final response = await _createDio().post(
      _authConfig.endpoint!,
      data: body,
    );

    if(response.data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }

    await _authConfig.onRefreshSuccess?.call(response.data);
  }

  Dio _createDio({String? baseUrl}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? _dio.options.baseUrl,
        connectTimeout: _timeOut,
        receiveTimeout: _timeOut,
        sendTimeout: _timeOut,
      ),
    );

    if(kDebugMode) {
      dio.interceptors.add(
        NetworkDevLogger(showTokenValue: _showTokenValue),
      );
    }

    return dio;
  }

  void _triggerAuthErrorAndThrowIfNeeded() {
    _onAuthenticationError();

    if(_authConfig.blockOnAuthenticationError) {
      throw SessionExpiredException();
    }
  }

  void _handleAuthenticationError(
      DioException err,
      ErrorInterceptorHandler handler) {
    _triggerAuthErrorAndThrowIfNeeded();
    handler.next(err);
  }

  void _onAuthenticationError() {
    if(_isError) return;

    _isError = true;
    _authConfig.onAuthenticationError?.call();
  }

  DateTime _parseDate(String value) {
    final match = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{4}) (\d{1,2}):(\d{1,2})$',
    ).firstMatch(value.trim());

    if(match == null) {
      throw FormatException("Invalid token time format 'dd/MM/yyyy HH:mm': $value",);
    }

    return DateTime(
      int.parse(match.group(3)!), // yyyy
      int.parse(match.group(2)!), // MM
      int.parse(match.group(1)!), // dd
      int.parse(match.group(4)!), // HH
      int.parse(match.group(5)!), // mm
    );
  }
}