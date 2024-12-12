// user_model.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UserModel {
  // Singleton pattern
  static final UserModel instance = UserModel._internal();

  factory UserModel() {
    return instance;
  }

  UserModel._internal();

  String? email;
  String? role;
  String? token;

  final FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<void> saveToken(String token) async {
    this.token = token;
    await _storage.write(key: 'jwt_token', value: token);
  }

  Future<void> loadToken() async {
    token = await _storage.read(key: 'jwt_token');
  }

  Future<void> clearToken() async {
    token = null;
    await _storage.delete(key: 'jwt_token');
  }
}