import 'dart:convert';

import 'package:flutter/foundation.dart';
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
    required this.focusPoints,
    required this.memory,
    required this.lastCallDaysAgo,
  });

  final String callId;
  final String model;
  final String token;
  final String tokenKind; // 'ephemeral' | 'dev_raw_key'
  final int remainingSeconds;

  /// From the user's latest report — woven into the coach's prompt.
  final List<String> focusPoints;

  /// What the coach "remembers" about this learner from recent calls.
  final String memory;
  final int? lastCallDaysAgo;
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
  const TranscriptTurn({
    required this.role,
    required this.text,
    this.tStartMs = 0,
    this.tEndMs = 0,
  });
  final String role; // 'user' | 'assistant'
  final String text;

  /// Milliseconds since call start — the backend derives talk-time and
  /// pace metrics from these.
  final int tStartMs;
  final int tEndMs;

  Map<String, Object> toJson() => {
        'role': role,
        'text': text,
        't_start_ms': tStartMs,
        't_end_ms': tEndMs,
      };
}

/// GET /v1/me/week — the Home screen's "Your week" card.
class WeekSummary {
  const WeekSummary({
    required this.calls,
    required this.minutes,
    required this.activeDays,
    required this.avgOverall,
    required this.deltaOverall,
    required this.topFocus,
    required this.line,
  });

  final int calls;
  final int minutes;
  final int activeDays;
  final int? avgOverall;
  final int? deltaOverall;
  final String topFocus;
  final String line;

  bool get isEmpty => calls == 0;
}

class PracticeExercise {
  const PracticeExercise({
    required this.kind,
    required this.prompt,
    required this.answer,
    required this.why,
  });

  final String kind; // 'fix' | 'choose' | 'upgrade'
  final String prompt;
  final String answer;
  final String why;
}

class PracticePack {
  const PracticePack({
    required this.exercises,
    required this.mistakes,
    required this.vocab,
  });

  final List<PracticeExercise> exercises;
  final List<Map<String, dynamic>> mistakes; // {said, better, why}
  final List<Map<String, dynamic>> vocab; // {used, better}

  bool get isEmpty => exercises.isEmpty && mistakes.isEmpty && vocab.isEmpty;
}

abstract final class Api {
  static Uri _u(String path) => Uri.parse('${Config.backendUrl}$path');

  static Map<String, String> get _headers => {
        'content-type': 'application/json',
        'authorization':
            'Bearer ${Supabase.instance.client.auth.currentSession?.accessToken ?? ''}',
      };

  /// 401 usually means a stale access token — refresh the session once and
  /// retry before giving up.
  static Future<http.Response> _getWithRefresh(Uri url) async {
    var resp = await http
        .get(url, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 401) {
      debugPrint('api: 401 from $url — refreshing session and retrying');
      await Supabase.instance.client.auth.refreshSession();
      resp = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 15));
    }
    return resp;
  }

  static Future<Limits> limits() async {
    try {
      final resp = await _getWithRefresh(_u('/v1/me/limits'));
      if (resp.statusCode != 200) {
        debugPrint(
            'api: limits ${resp.statusCode}: ${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
        throw ApiException('limits failed: ${resp.statusCode}');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return Limits(
        tier: data['tier'] as String,
        allowanceSeconds: data['daily_allowance_seconds'] as int,
        remainingSeconds: data['remaining_seconds'] as int,
      );
    } catch (e) {
      debugPrint('api: limits error: $e');
      rethrow;
    }
  }

  static Future<SessionGrant> startSession({
    String scenario = 'casual',
    String persona = 'emma',
  }) async {
    var resp = await http
        .post(
          _u('/v1/session'),
          headers: _headers,
          body: jsonEncode({'scenario': scenario, 'persona': persona}),
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 401) {
      debugPrint('api: session 401 — refreshing session and retrying');
      await Supabase.instance.client.auth.refreshSession();
      resp = await http
          .post(
            _u('/v1/session'),
            headers: _headers,
            body: jsonEncode({'scenario': scenario, 'persona': persona}),
          )
          .timeout(const Duration(seconds: 20));
    }
    if (resp.statusCode == 429) throw const OutOfMinutesException();
    if (resp.statusCode != 200) {
      debugPrint('api: session ${resp.statusCode}: ${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
      throw ApiException('session failed: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return SessionGrant(
      callId: data['call_id'] as String,
      model: data['model'] as String,
      token: data['token'] as String,
      tokenKind: data['token_kind'] as String,
      remainingSeconds: data['remaining_seconds'] as int,
      focusPoints: ((data['focus_points'] as List?) ?? [])
          .map((e) => e.toString())
          .toList(),
      memory: (data['memory'] as String?) ?? '',
      lastCallDaysAgo: data['last_call_days_ago'] as int?,
    );
  }

  // Cached so tab switches don't re-trigger the backend's summary-line
  // generation; a finished call invalidates it via [invalidateWeek].
  static WeekSummary? _weekCache;
  static DateTime? _weekCacheAt;

  static void invalidateWeek() {
    _weekCache = null;
    _weekCacheAt = null;
  }

  static Future<WeekSummary> week() async {
    final cached = _weekCache;
    if (cached != null &&
        _weekCacheAt != null &&
        DateTime.now().difference(_weekCacheAt!) <
            const Duration(minutes: 30)) {
      return cached;
    }
    final resp = await _getWithRefresh(_u('/v1/me/week'))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      debugPrint('api: week ${resp.statusCode}');
      throw ApiException('week failed: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final week = WeekSummary(
      calls: (data['calls'] as num?)?.toInt() ?? 0,
      minutes: (data['minutes'] as num?)?.toInt() ?? 0,
      activeDays: (data['active_days'] as num?)?.toInt() ?? 0,
      avgOverall: (data['avg_overall'] as num?)?.toInt(),
      deltaOverall: (data['delta_overall'] as num?)?.toInt(),
      topFocus: (data['top_focus'] as String?) ?? '',
      line: (data['line'] as String?) ?? '',
    );
    _weekCache = week;
    _weekCacheAt = DateTime.now();
    return week;
  }

  static Future<PracticePack> practice() async {
    final resp = await _getWithRefresh(_u('/v1/practice'))
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) {
      debugPrint('api: practice ${resp.statusCode}');
      throw ApiException('practice failed: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    List<Map<String, dynamic>> maps(String key) =>
        ((data[key] as List?) ?? [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
    return PracticePack(
      exercises: [
        for (final e in maps('exercises'))
          PracticeExercise(
            kind: (e['kind'] ?? '') as String,
            prompt: (e['prompt'] ?? '') as String,
            answer: (e['answer'] ?? '') as String,
            why: (e['why'] ?? '') as String,
          ),
      ],
      mistakes: maps('source_mistakes'),
      vocab: maps('source_vocab'),
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
