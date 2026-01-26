import 'package:dio/dio.dart';

/// HTTP 请求方法枚举
enum HttpMethod { get, post, put, delete, patch, head, options }

/// HTTP 请求配置
///
/// 封装单次 HTTP 请求所需的全部参数，提供类型安全的配置方式。
///
/// ## 示例
///
/// ```dart
/// // GET 请求
/// final config = HttpRequestConfig(
///   path: '/users',
///   method: HttpMethod.get,
///   queryParameters: {'page': 1, 'limit': 10},
/// );
///
/// // POST 请求
/// final config = HttpRequestConfig(
///   path: '/users',
///   method: HttpMethod.post,
///   data: {'name': 'John', 'email': 'john@example.com'},
/// );
///
/// // 文件上传
/// final config = HttpRequestConfig(
///   path: '/upload',
///   method: HttpMethod.post,
///   data: FormData.fromMap({'file': await MultipartFile.fromFile(path)}),
///   onSendProgress: (sent, total) => print('$sent / $total'),
/// );
/// ```
class HttpRequestConfig {
  /// 请求路径（相对于 baseUrl 或完整 URL）
  final String path;

  /// HTTP 方法，默认为 GET
  final HttpMethod method;

  /// 请求体数据（用于 POST/PUT/PATCH）
  ///
  /// 支持的类型：
  /// - `Map<String, dynamic>` - 自动序列化为 JSON
  /// - `FormData` - 文件上传
  /// - `String` - 原始字符串
  final dynamic data;

  /// URL 查询参数
  final Map<String, dynamic>? queryParameters;

  /// 自定义请求头
  final Map<String, dynamic>? headers;

  /// 连接超时时间
  final Duration? connectTimeout;

  /// 接收超时时间
  final Duration? receiveTimeout;

  /// 发送超时时间
  final Duration? sendTimeout;

  /// 响应类型
  final ResponseType? responseType;

  /// 内容类型
  final String? contentType;

  /// 上传进度回调
  ///
  /// ```dart
  /// onSendProgress: (int sent, int total) {
  ///   final progress = sent / total;
  ///   print('Upload: ${(progress * 100).toStringAsFixed(1)}%');
  /// }
  /// ```
  final ProgressCallback? onSendProgress;

  /// 下载进度回调
  ///
  /// ```dart
  /// onReceiveProgress: (int received, int total) {
  ///   if (total != -1) {
  ///     final progress = received / total;
  ///     print('Download: ${(progress * 100).toStringAsFixed(1)}%');
  ///   }
  /// }
  /// ```
  final ProgressCallback? onReceiveProgress;

  /// 请求的额外配置
  final Options? extra;

  const HttpRequestConfig({
    required this.path,
    this.method = HttpMethod.get,
    this.data,
    this.queryParameters,
    this.headers,
    this.connectTimeout,
    this.receiveTimeout,
    this.sendTimeout,
    this.responseType,
    this.contentType,
    this.onSendProgress,
    this.onReceiveProgress,
    this.extra,
  });

  /// 创建 GET 请求配置
  ///
  /// ```dart
  /// final config = HttpRequestConfig.get(
  ///   '/users',
  ///   queryParameters: {'page': 1},
  /// );
  /// ```
  factory HttpRequestConfig.get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    ResponseType? responseType,
    ProgressCallback? onReceiveProgress,
  }) {
    return HttpRequestConfig(
      path: path,
      method: HttpMethod.get,
      queryParameters: queryParameters,
      headers: headers,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      responseType: responseType,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// 创建 POST 请求配置
  ///
  /// ```dart
  /// final config = HttpRequestConfig.post(
  ///   '/users',
  ///   data: {'name': 'John'},
  /// );
  /// ```
  factory HttpRequestConfig.post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    String? contentType,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return HttpRequestConfig(
      path: path,
      method: HttpMethod.post,
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      contentType: contentType,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// 创建 PUT 请求配置
  factory HttpRequestConfig.put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    String? contentType,
    ProgressCallback? onSendProgress,
  }) {
    return HttpRequestConfig(
      path: path,
      method: HttpMethod.put,
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      contentType: contentType,
      onSendProgress: onSendProgress,
    );
  }

  /// 创建 DELETE 请求配置
  factory HttpRequestConfig.delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Duration? connectTimeout,
    Duration? receiveTimeout,
  }) {
    return HttpRequestConfig(
      path: path,
      method: HttpMethod.delete,
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
    );
  }

  /// 创建 PATCH 请求配置
  factory HttpRequestConfig.patch(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    String? contentType,
    ProgressCallback? onSendProgress,
  }) {
    return HttpRequestConfig(
      path: path,
      method: HttpMethod.patch,
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      contentType: contentType,
      onSendProgress: onSendProgress,
    );
  }

  /// 复制并修改配置
  HttpRequestConfig copyWith({
    String? path,
    HttpMethod? method,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    ResponseType? responseType,
    String? contentType,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    Options? extra,
  }) {
    return HttpRequestConfig(
      path: path ?? this.path,
      method: method ?? this.method,
      data: data ?? this.data,
      queryParameters: queryParameters ?? this.queryParameters,
      headers: headers ?? this.headers,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      responseType: responseType ?? this.responseType,
      contentType: contentType ?? this.contentType,
      onSendProgress: onSendProgress ?? this.onSendProgress,
      onReceiveProgress: onReceiveProgress ?? this.onReceiveProgress,
      extra: extra ?? this.extra,
    );
  }
}

/// Dio HTTP 适配器
///
/// 将 [HttpRequestConfig] 转换为 Dio 请求，提供统一的 HTTP 语义层。
/// 支持请求/响应拦截器、全局配置、错误转换等功能。
///
/// ## 基础用法
///
/// ```dart
/// final adapter = DioHttpAdapter(
///   dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
/// );
///
/// // 执行请求
/// final response = await adapter.request<Map<String, dynamic>>(
///   HttpRequestConfig.get('/users/1'),
/// );
/// print(response.data);
/// ```
///
/// ## 与 useRequest 集成
///
/// ```dart
/// final adapter = DioHttpAdapter.withBaseUrl('https://api.example.com');
///
/// final result = useRequest<User, HttpRequestConfig>(
///   (config) => adapter.request<Map<String, dynamic>>(config)
///       .then((res) => User.fromJson(res.data!)),
///   options: UseRequestOptions(
///     manual: true,
///   ),
/// );
///
/// // 发起 GET 请求
/// result.run(HttpRequestConfig.get('/users/1'));
///
/// // 发起 POST 请求
/// result.run(HttpRequestConfig.post('/users', data: {'name': 'John'}));
/// ```
///
/// ## 添加拦截器
///
/// ```dart
/// final adapter = DioHttpAdapter(
///   dio: Dio()..interceptors.addAll([
///     LogInterceptor(requestBody: true, responseBody: true),
///     InterceptorsWrapper(
///       onRequest: (options, handler) {
///         options.headers['Authorization'] = 'Bearer $token';
///         handler.next(options);
///       },
///     ),
///   ]),
/// );
/// ```
class DioHttpAdapter {
  /// Dio 实例
  final Dio dio;

  /// 响应数据转换器
  ///
  /// 用于将 Response.data 转换为目标类型，默认直接返回原始数据。
  /// 可用于统一处理 API 响应格式。
  ///
  /// ```dart
  /// final adapter = DioHttpAdapter(
  ///   dio: dio,
  ///   responseTransformer: (data) {
  ///     // 假设 API 返回格式为 { code: 0, data: {...}, message: '' }
  ///     if (data is Map && data['code'] == 0) {
  ///       return data['data'];
  ///     }
  ///     throw ApiException(data['message']);
  ///   },
  /// );
  /// ```
  final dynamic Function(dynamic data)? responseTransformer;

  /// 错误转换器
  ///
  /// 用于将 DioException 转换为业务异常。
  ///
  /// ```dart
  /// final adapter = DioHttpAdapter(
  ///   dio: dio,
  ///   errorTransformer: (error) {
  ///     if (error.response?.statusCode == 401) {
  ///       return UnauthorizedException();
  ///     }
  ///     return error;
  ///   },
  /// );
  /// ```
  final dynamic Function(DioException error)? errorTransformer;

  DioHttpAdapter({
    required this.dio,
    this.responseTransformer,
    this.errorTransformer,
  });

  /// 使用 baseUrl 创建适配器
  ///
  /// ```dart
  /// final adapter = DioHttpAdapter.withBaseUrl(
  ///   'https://api.example.com',
  ///   connectTimeout: Duration(seconds: 10),
  ///   receiveTimeout: Duration(seconds: 30),
  /// );
  /// ```
  factory DioHttpAdapter.withBaseUrl(
    String baseUrl, {
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    Map<String, dynamic>? headers,
    dynamic Function(dynamic data)? responseTransformer,
    dynamic Function(DioException error)? errorTransformer,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        sendTimeout: sendTimeout,
        headers: headers,
      ),
    );

    return DioHttpAdapter(
      dio: dio,
      responseTransformer: responseTransformer,
      errorTransformer: errorTransformer,
    );
  }

  /// 执行 HTTP 请求
  ///
  /// [config] 请求配置
  /// [cancelToken] 可选的取消令牌
  ///
  /// 返回 Dio [Response] 对象，包含响应数据、状态码、头部等信息。
  ///
  /// ## 示例
  ///
  /// ```dart
  /// try {
  ///   final response = await adapter.request<Map<String, dynamic>>(
  ///     HttpRequestConfig.get('/users/1'),
  ///   );
  ///   print('Status: ${response.statusCode}');
  ///   print('Data: ${response.data}');
  /// } on DioException catch (e) {
  ///   print('Error: ${e.message}');
  /// }
  /// ```
  Future<Response<T>> request<T>(
    HttpRequestConfig config, {
    CancelToken? cancelToken,
  }) async {
    try {
      final base = dio.options;

      final mergedHeaders = <String, dynamic>{
        ...base.headers,
        ...?config.headers,
        ...?config.extra?.headers,
      };

      final mergedQueryParameters = <String, dynamic>{
        ...base.queryParameters,
        ...?config.queryParameters,
      };

      final requestOptions = RequestOptions(
        path: config.path,
        method: _methodToString(config.method),
        data: config.data,
        queryParameters: mergedQueryParameters,
        baseUrl: base.baseUrl,
        connectTimeout: config.connectTimeout ?? base.connectTimeout,
        sendTimeout: config.sendTimeout ?? base.sendTimeout,
        receiveTimeout: config.receiveTimeout ?? base.receiveTimeout,
        headers: mergedHeaders,
        responseType:
            config.responseType ??
            config.extra?.responseType ??
            base.responseType,
        contentType:
            config.contentType ?? config.extra?.contentType ?? base.contentType,
        extra: {...base.extra, ...?config.extra?.extra},
        cancelToken: cancelToken,
        onSendProgress: config.onSendProgress,
        onReceiveProgress: config.onReceiveProgress,
      );

      // 执行请求（使用 fetch 以支持 per-request connectTimeout）
      final response = await dio.fetch<T>(requestOptions);

      // 应用响应转换器
      if (responseTransformer != null && response.data != null) {
        final transformedData = responseTransformer!(response.data);
        return Response<T>(
          data: transformedData as T?,
          statusCode: response.statusCode,
          statusMessage: response.statusMessage,
          headers: response.headers,
          requestOptions: response.requestOptions,
          redirects: response.redirects,
          isRedirect: response.isRedirect,
          extra: response.extra,
        );
      }

      return response;
    } on DioException catch (e) {
      // 应用错误转换器
      if (errorTransformer != null) {
        throw errorTransformer!(e);
      }
      rethrow;
    }
  }

  /// 执行 GET 请求的便捷方法
  ///
  /// ```dart
  /// final response = await adapter.get<List<dynamic>>('/users');
  /// ```
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
    return request<T>(
      HttpRequestConfig.get(
        path,
        queryParameters: queryParameters,
        headers: headers,
        onReceiveProgress: onReceiveProgress,
      ),
      cancelToken: cancelToken,
    );
  }

  /// 执行 POST 请求的便捷方法
  ///
  /// ```dart
  /// final response = await adapter.post<Map<String, dynamic>>(
  ///   '/users',
  ///   data: {'name': 'John'},
  /// );
  /// ```
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return request<T>(
      HttpRequestConfig.post(
        path,
        data: data,
        queryParameters: queryParameters,
        headers: headers,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      ),
      cancelToken: cancelToken,
    );
  }

  /// 执行 PUT 请求的便捷方法
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) {
    return request<T>(
      HttpRequestConfig.put(
        path,
        data: data,
        queryParameters: queryParameters,
        headers: headers,
        onSendProgress: onSendProgress,
      ),
      cancelToken: cancelToken,
    );
  }

  /// 执行 DELETE 请求的便捷方法
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) {
    return request<T>(
      HttpRequestConfig.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        headers: headers,
      ),
      cancelToken: cancelToken,
    );
  }

  /// 执行 PATCH 请求的便捷方法
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) {
    return request<T>(
      HttpRequestConfig.patch(
        path,
        data: data,
        queryParameters: queryParameters,
        headers: headers,
        onSendProgress: onSendProgress,
      ),
      cancelToken: cancelToken,
    );
  }

  /// 上传文件的便捷方法
  ///
  /// ```dart
  /// final response = await adapter.upload<Map<String, dynamic>>(
  ///   '/upload',
  ///   file: await MultipartFile.fromFile('/path/to/file.jpg'),
  ///   fieldName: 'image',
  ///   extraFields: {'description': 'My photo'},
  ///   onProgress: (sent, total) {
  ///     print('Progress: ${(sent / total * 100).toStringAsFixed(1)}%');
  ///   },
  /// );
  /// ```
  Future<Response<T>> upload<T>(
    String path, {
    required MultipartFile file,
    String fieldName = 'file',
    Map<String, dynamic>? extraFields,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onProgress,
  }) {
    final formData = FormData.fromMap({fieldName: file, ...?extraFields});

    return request<T>(
      HttpRequestConfig.post(
        path,
        data: formData,
        headers: headers,
        onSendProgress: onProgress,
      ),
      cancelToken: cancelToken,
    );
  }

  /// 上传文件的便捷别名（与 README 示例对齐）
  ///
  /// 等价于 [upload]，但直接接受 filePath。
  Future<Response<T>> uploadFile<T>(
    String path, {
    required String filePath,
    String fileField = 'file',
    String? filename,
    Map<String, dynamic>? extraFields,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onProgress,
  }) async {
    final file = await MultipartFile.fromFile(filePath, filename: filename);
    return upload<T>(
      path,
      file: file,
      fieldName: fileField,
      extraFields: extraFields,
      headers: headers,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  }

  /// 下载文件的便捷方法
  ///
  /// ```dart
  /// await adapter.download(
  ///   '/files/document.pdf',
  ///   '/local/path/document.pdf',
  ///   onProgress: (received, total) {
  ///     if (total != -1) {
  ///       print('Progress: ${(received / total * 100).toStringAsFixed(1)}%');
  ///     }
  ///   },
  /// );
  /// ```
  Future<Response> download(
    String urlPath,
    String savePath, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onProgress,
    bool deleteOnError = true,
  }) {
    return dio.download(
      urlPath,
      savePath,
      queryParameters: queryParameters,
      options: Options(headers: headers),
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
      deleteOnError: deleteOnError,
    );
  }

  /// 下载文件的便捷别名（与 README 示例对齐）
  ///
  /// 等价于 [download]。
  Future<Response> downloadFile(
    String urlPath, {
    required String savePath,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    ProgressCallback? onProgress,
    bool deleteOnError = true,
  }) {
    return download(
      urlPath,
      savePath,
      queryParameters: queryParameters,
      headers: headers,
      cancelToken: cancelToken,
      onProgress: onProgress,
      deleteOnError: deleteOnError,
    );
  }

  /// 将 HttpMethod 枚举转换为字符串
  String _methodToString(HttpMethod method) {
    switch (method) {
      case HttpMethod.get:
        return 'GET';
      case HttpMethod.post:
        return 'POST';
      case HttpMethod.put:
        return 'PUT';
      case HttpMethod.delete:
        return 'DELETE';
      case HttpMethod.patch:
        return 'PATCH';
      case HttpMethod.head:
        return 'HEAD';
      case HttpMethod.options:
        return 'OPTIONS';
    }
  }
}

/// 创建与 useRequest 集成的 Service 函数
///
/// 将 DioHttpAdapter 包装为 useRequest 可用的 Service 类型。
///
/// ## 示例
///
/// ```dart
/// final adapter = DioHttpAdapter.withBaseUrl('https://api.example.com');
///
/// // 创建返回原始 Response 的 service
/// final rawService = createDioService<Response<dynamic>>(adapter);
///
/// // 创建返回转换后数据的 service
/// final userService = createDioService<User>(
///   adapter,
///   transformer: (response) => User.fromJson(response.data),
/// );
///
/// // 在 useRequest 中使用
/// final result = useRequest<User, HttpRequestConfig>(
///   userService,
///   options: UseRequestOptions(manual: true),
/// );
///
/// result.run(HttpRequestConfig.get('/users/1'));
/// ```
Future<T> Function(HttpRequestConfig config) createDioService<T>(
  DioHttpAdapter adapter, {
  T Function(Response response)? transformer,
}) {
  return (HttpRequestConfig config) async {
    final response = await adapter.request<dynamic>(config);
    if (transformer != null) {
      return transformer(response);
    }
    return response as T;
  };
}
