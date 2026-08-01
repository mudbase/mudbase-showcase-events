import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:mudbase_sdk/mudbase_sdk.dart';

import 'mudbase_exception.dart';

/// Auth calls against the real Mudbase project/Multi-Role feature. Ported
/// from the sibling kanban/social/ecommerce Flutter apps'
/// `core/auth_service.dart` - same reasoning, same bypass of the generated
/// wrapper classes:
///
/// Every response model the SDK types for auth (`LoginLocalUser200Response`,
/// `User`, ...) declares `role` but not `customRole` - built_value's
/// standard JSON deserializer silently drops unknown fields rather than
/// erroring, so calling through the typed wrapper would silently lose
/// exactly the field this app gates every write on (`organizer`/`attendee`).
///
/// Unlike the sibling ports, this service has no `registerWithRole` method
/// exposed here for the primary demo path - the task brief for this app
/// names two already-registered, already-verified demo accounts as the
/// primary smoke-test path (registration is rate-limited and shared across
/// concurrently-worked sibling projects). `register` is still implemented
/// (mirroring the reference web app's own nice-to-have `/register` page)
/// since this app, unlike kanban, ships a real two-role signup flow.
///
/// Request bodies still use the SDK's real generated builder class
/// (`LoginLocalUserRequest`) and its own `Serializers` to produce the wire
/// payload, so the request shape is guaranteed to match what the generated
/// code would have sent - only the response side is handled manually.
class AuthService {
  const AuthService(this._sdk, this._projectId);

  final MudbaseSdk _sdk;
  final String _projectId;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final request = LoginLocalUserRequest(
      (b) => b
        ..email = email
        ..password = password
        ..projectId = _projectId,
    );
    final body = _sdk.serializers.serialize(
      request,
      specifiedType: const FullType(LoginLocalUserRequest),
    );
    try {
      final response = await _sdk.dio.post<dynamic>(
        '/api/auth/local/login',
        data: body,
        options: Options(contentType: 'application/json'),
      );
      return _asJsonMap(response);
    } on DioException catch (error) {
      throw MudbaseException.fromDioException(error);
    }
  }

  /// `POST /api/auth/local/signup/:role` - the signup validator explicitly
  /// rejects `role`/`customRole` in the request body (`.unknown(false)`, a
  /// deliberate anti-role-injection control) - the role is taken only from
  /// the URL path segment, so it is never spread into the body. No generated
  /// builder class covers this per-role path shape, so the body is
  /// constructed by hand, same as the sibling ports' own signup methods.
  Future<Map<String, dynamic>> register({
    required String role,
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      final response = await _sdk.dio.post<dynamic>(
        '/api/auth/local/signup/$role',
        data: {
          'email': email,
          'password': password,
          'firstName': firstName,
          'lastName': lastName,
          'agreedToTerms': true,
          'projectId': _projectId,
        },
        options: Options(contentType: 'application/json'),
      );
      return _asJsonMap(response);
    } on DioException catch (error) {
      throw MudbaseException.fromDioException(error);
    }
  }

  /// `POST /api/auth/refresh` - exchanges a still-valid refresh token for a
  /// new access/refresh pair. No generated builder class exists for this
  /// request (the bundled OpenAPI spec has no refresh endpoint at all), so
  /// the body is constructed by hand, same as the sibling ports.
  Future<Map<String, dynamic>> refreshSession(String refreshToken) async {
    try {
      final response = await _sdk.dio.post<dynamic>(
        '/api/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(contentType: 'application/json'),
      );
      return _asJsonMap(response);
    } on DioException catch (error) {
      throw MudbaseException.fromDioException(error);
    }
  }

  /// `GET /api/auth/session` - both org- and project-scoped bearer tokens
  /// are accepted by this endpoint, so it works the same right after a
  /// local login as it does on cold-start session restore.
  Future<Map<String, dynamic>> getSession(String token) async {
    try {
      final response = await _sdk.dio.get<dynamic>(
        '/api/auth/session',
        queryParameters: {'projectId': _projectId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return _asJsonMap(response);
    } on DioException catch (error) {
      throw MudbaseException.fromDioException(error);
    }
  }

  Future<void> logout(String token) async {
    try {
      await _sdk.dio.post<dynamic>(
        '/api/auth/logout',
        data: {'projectId': _projectId},
        options: Options(
          contentType: 'application/json',
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
    } on DioException catch (error) {
      // Logout is a best-effort server-side revoke - the client clears its
      // own token regardless (see AuthController.logout), so a failed
      // revoke call must not block the local sign-out.
      if (error.response?.statusCode == 401) return;
      throw MudbaseException.fromDioException(error);
    }
  }

  Map<String, dynamic> _asJsonMap(Response<dynamic> response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    throw const MudbaseException(
      'Unexpected response shape from the server.',
      0,
    );
  }
}
