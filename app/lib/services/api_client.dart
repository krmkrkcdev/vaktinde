import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Sunucunun döndürdüğü hata.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  /// Oturum düştü; kullanıcının tekrar giriş yapması gerekir.
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Ağa erişilemedi. Çevrimdışı öncelikli olduğumuz için bu bir hata değil,
/// beklenen bir durumdur: senkronizasyon bir sonraki fırsatta denenir.
class NetworkUnavailableException implements Exception {
  const NetworkUnavailableException();

  @override
  String toString() => 'Sunucuya ulaşılamadı';
}

/// Vaktinde API'sinin ince bir sarmalayıcısı.
///
/// Token yenilemeyi kendisi yapar: bir istek 401 dönerse yenileme tokeni ile
/// bir kez yeniler ve isteği tekrarlar.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  String? _accessToken;
  String? _refreshToken;

  /// Yenileme tokeni değiştiğinde çağrılır; güvenli depoya yazmak içindir.
  void Function(String access, String refresh)? onTokensChanged;

  /// Yenileme de başarısız olduğunda çağrılır; kullanıcı çıkarılmalıdır.
  void Function()? onSessionExpired;

  bool get hasSession => _refreshToken != null;

  void setTokens(String? access, String? refresh) {
    _accessToken = access;
    _refreshToken = refresh;
  }

  void clear() {
    _accessToken = null;
    _refreshToken = null;
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  // ------------------------------------------------------------------ auth

  Future<void> register(String email, String password) async {
    final body = await _send(
      (h) => _http.post(
        _uri('/auth/register'),
        headers: h,
        body: jsonEncode({'email': email, 'password': password}),
      ),
      authenticated: false,
    );
    _storeTokens(body);
  }

  Future<void> login(String email, String password) async {
    final body = await _send(
      (h) => _http.post(
        _uri('/auth/login'),
        headers: h,
        body: jsonEncode({'email': email, 'password': password}),
      ),
      authenticated: false,
    );
    _storeTokens(body);
  }

  Future<Map<String, Object?>> me() async {
    return await _send((h) => _http.get(_uri('/auth/me'), headers: h))
        as Map<String, Object?>;
  }

  void _storeTokens(Object? body) {
    final map = body as Map<String, Object?>;
    _accessToken = map['access_token'] as String;
    _refreshToken = map['refresh_token'] as String;
    onTokensChanged?.call(_accessToken!, _refreshToken!);
  }

  // ------------------------------------------------------------------ sync

  Future<Map<String, Object?>> fetchChanges(int since) async {
    return await _send(
      (h) => _http.get(_uri('/sync/changes', {'since': '$since'}), headers: h),
    ) as Map<String, Object?>;
  }

  Future<Map<String, Object?>> push(List<Map<String, Object?>> reminders) async {
    return await _send(
      (h) => _http.post(
        _uri('/sync/push'),
        headers: h,
        body: jsonEncode({'reminders': reminders}),
      ),
    ) as Map<String, Object?>;
  }

  // ---------------------------------------------------------------- photos

  Future<void> uploadPhoto({
    required String photoId,
    required String reminderId,
    required File file,
  }) async {
    Future<http.Response> attempt(Map<String, String> headers) async {
      final request = http.MultipartRequest(
        'PUT',
        _uri('/photos/$photoId', {'reminder_id': reminderId}),
      )
        ..headers.addAll(headers)
        ..files.add(await http.MultipartFile.fromPath('file', file.path));
      return http.Response.fromStream(await _http.send(request));
    }

    await _send((h) => attempt(h), json: false);
  }

  Future<List<int>> downloadPhoto(String photoId) async {
    final response = await _sendRaw((h) => _http.get(_uri('/photos/$photoId'), headers: h));
    return response.bodyBytes;
  }

  Future<void> deletePhoto(String photoId) async {
    await _send((h) => _http.delete(_uri('/photos/$photoId'), headers: h));
  }

  // --------------------------------------------------------------- dahili

  Future<Object?> _send(
    Future<http.Response> Function(Map<String, String> headers) request, {
    bool authenticated = true,
    bool json = true,
  }) async {
    final response = await _sendRaw(request, authenticated: authenticated, json: json);
    if (response.body.isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<http.Response> _sendRaw(
    Future<http.Response> Function(Map<String, String> headers) request, {
    bool authenticated = true,
    bool json = true,
  }) async {
    http.Response response;
    try {
      response = await request(_headers(json: json));
    } on SocketException {
      throw const NetworkUnavailableException();
    } on http.ClientException {
      throw const NetworkUnavailableException();
    }

    // Access tokenın ömrü kısa; süresi dolduysa sessizce yenileyip tekrarlarız.
    if (response.statusCode == 401 && authenticated && _refreshToken != null) {
      if (await _refresh()) {
        try {
          response = await request(_headers(json: json));
        } on SocketException {
          throw const NetworkUnavailableException();
        }
      } else {
        onSessionExpired?.call();
      }
    }

    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
    return response;
  }

  Future<bool> _refresh() async {
    try {
      final response = await _http.post(
        _uri('/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      );
      if (response.statusCode != 200) return false;
      _storeTokens(jsonDecode(utf8.decode(response.bodyBytes)));
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['detail'] is String) return body['detail'] as String;
      if (body is Map && body['detail'] is List) {
        // Pydantic doğrulama hatası.
        return 'Girilen bilgiler geçersiz';
      }
    } catch (_) {
      // Gövde JSON değilse aşağıdaki genel mesaja düşülür.
    }
    return 'Sunucu hatası (${response.statusCode})';
  }
}
