import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({required String baseUrl, String? token})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            headers: token == null ? null : {'Authorization': 'Bearer $token'},
          ),
        );

  final Dio _dio;

  Dio get raw => _dio;
}
