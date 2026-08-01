import 'package:dio/dio.dart';
import 'package:mudbase_showcase_events/core/mudbase_exception.dart';
import 'package:test/test.dart';

void main() {
  group('MudbaseException.fromDioException', () {
    test('reads the "error" field from a JSON error response', () {
      final requestOptions = RequestOptions(path: '/x');
      final response = Response<dynamic>(
        requestOptions: requestOptions,
        statusCode: 403,
        data: {'error': 'Insufficient permissions'},
      );
      final dioError = DioException(
        requestOptions: requestOptions,
        response: response,
      );

      final exception = MudbaseException.fromDioException(dioError);
      expect(exception.statusCode, 403);
      expect(exception.message, 'Insufficient permissions');
    });

    test('falls back to "message" field when "error" is absent', () {
      final requestOptions = RequestOptions(path: '/x');
      final response = Response<dynamic>(
        requestOptions: requestOptions,
        statusCode: 400,
        data: {'message': 'Bad request'},
      );
      final dioError = DioException(
        requestOptions: requestOptions,
        response: response,
      );

      final exception = MudbaseException.fromDioException(dioError);
      expect(exception.message, 'Bad request');
    });

    test('reads an optional error code', () {
      final requestOptions = RequestOptions(path: '/x');
      final response = Response<dynamic>(
        requestOptions: requestOptions,
        statusCode: 401,
        data: {
          'error': 'Please verify your email',
          'code': 'EMAIL_VERIFICATION_REQUIRED',
        },
      );
      final dioError = DioException(
        requestOptions: requestOptions,
        response: response,
      );

      final exception = MudbaseException.fromDioException(dioError);
      expect(exception.code, 'EMAIL_VERIFICATION_REQUIRED');
    });

    test('produces a network message when there is no response at all', () {
      final requestOptions = RequestOptions(path: '/x');
      final dioError = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionTimeout,
      );

      final exception = MudbaseException.fromDioException(dioError);
      expect(exception.statusCode, 0);
      expect(exception.message, contains('timed out'));
    });

    test('toString returns the message', () {
      const exception = MudbaseException('Something failed', 500);
      expect(exception.toString(), 'Something failed');
    });
  });
}
