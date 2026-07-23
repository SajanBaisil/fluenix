import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// The Flutter side of backend/app/routes/session.py.
class OutOfMinutesException implements Exception {
  const OutOfMinutesException();
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SessionGrant {
  const SessionGrant({
    required this.callId,
    required this.model,
    required this.token,
    required this.tokenKind,
    required this.remainingSeconds,
  });

  final String callId;
  final String model;
  final String token;
  final String tokenKind; // 'ephemeral' | 'dev_raw_key'
  final int remainingSeconds;

  /// Query-string auth for the Live websocket.
  String get authQuery =>
      tokenKind == 'ephemeral' ? 'access_token=$token' : 'key=$token';
}

class Limits {
  const Limits({
    required this.tier,
    required this.allowanceSeconds,
    required this.remainingSeconds,
  });

  final String tier;
  final int allowanceSeconds;
  final int remainingSeconds;
}

class TranscriptTurn {
  const TranscriptTurn({required this.role, required this.text});
  final String role; // 'user' | 'assistant'
  final String text;

  Map<String, Object> toJson() => {'role': role, 'text': text};
}

abstract final class Api {
  static Uri _u(String path) => Uri.parse('${Config.backendUrl}$path');

  static Map<String, String> get _headers => {
        'content-type': 'application/json',
        'authorization':
            'Bearer ${Supabase.instance.client.auth.currentSession?.accessToken ?? ''}',
      };

  static Future<Limits> limits() async {
    final resp = await http
        .get(_u('/v1/me/limits'), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw ApiException('limits failed: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return Limits(
      tier: data['tier'] as String,
      allowanceSeconds: data['daily_allowance_seconds'] as int,
      remainingSeconds: data['remaining_seconds'] as int,
    );
  }

  static Future<SessionGrant> startSession({
    String scenario = 'casual',
    String persona = 'emma',
  }) async {
    final resp = await http
        .post(
          _u('/v1/session'),
          headers: _headers,
          body: jsonEncode({'scenario': scenario, 'persona': persona}),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 429) throw const OutOfMinutesException();
    if (resp.statusCode != 200) {
      throw ApiException('session failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return SessionGrant(
      callId: data['call_id'] as String,
      model: data['model'] as String,
      token: data['token'] as String,
      tokenKind: data['token_kind'] as String,
      remainingSeconds: data['remaining_seconds'] as int,
    );
  }

  static Future<void> endCall({
    required String callId,
    required int durationS,
    required List<TranscriptTurn> turns,
  }) async {
    final resp = await http
        .post(
          _u('/v1/calls/$callId/end'),
          headers: _headers,
          body: jsonEncode({
            'duration_s': durationS,
            'turns': turns.map((t) => t.toJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      throw ApiException('end call failed: ${resp.statusCode}');
    }
  }
}
