import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';

/// Progress over time (mockup 06): score trend, week streak, metric deltas.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => ProgressScreenState();
}

class ProgressScreenState extends State<ProgressScreen> {
  List<Map<String, dynamic>> _reports = const [];
  Set<String> _activeDays = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final reports = await Supabase.instance.client
          .from('reports')
          .select('overall, scores, filler_words, created_at, '
              'calls!inner(user_id)')
          .eq('calls.user_id', uid)
          .order('created_at', ascending: true)
          .limit(30);
      final weekAgo = DateTime.now()
          .subtract(const Duration(days: 6))
          .toIso8601String()
          .substring(0, 10);
      final progress = await Supabase.instance.client
          .from('user_progress')
          .select('date, minutes')
          .eq('user_id', uid)
          .gte('date', weekAgo);
      if (!mounted) return;
      setState(() {
        _reports = reports.cast<Map<String, dynamic>>();
        _activeDays = {
          for (final p in progress)
            if (((p['minutes'] as num?) ?? 0) > 0) p['date'] as String,
        };
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: !_loaded
            ? const Center(
                child: CircularProgressIndicator(color: Tokens.indigoSoft))
            : _reports.isEmpty
                ? _empty()
                : _content(),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.show_chart_rounded, size: 44, color: Tokens.faint),
            SizedBox(height: 16),
            Text(
              'No calls analyzed yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Finish a call and your progress will start showing here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Tokens.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final latest = _reports.last;
    final prev = _reports.length > 1 ? _reports[_reports.length - 2] : null;
    final latestScores =
        (latest['scores'] as Map?)?.cast<String, dynamic>() ?? {};
    final prevScores = (prev?['scores'] as Map?)?.cast<String, dynamic>();
    final overalls = [
      for (final r in _reports) ((r['overall'] as num?) ?? 0).toDouble(),
    ];
    final delta = overalls.length > 1
        ? (overalls.last - overalls.first).round()
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
      children: [
        const Text(
          'Progress',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Tokens.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Tokens.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Overall score · your calls',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (delta != null)
                    Text(
                      '${delta >= 0 ? '▲' : '▼'} ${delta.abs()}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: delta >= 0 ? Tokens.mint : Tokens.rose,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 120,
                width: double.infinity,
                child: CustomPaint(painter: _TrendPainter(overalls)),
              ),
            ],
          ),
        ),
        _sectionLabel('THIS WEEK'),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: Tokens.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Tokens.line),
          ),
          child: _weekDots(),
        ),
        _sectionLabel('LATEST CALL'),
        Row(
          children: [
            _tile('Grammar', latestScores['grammar'], prevScores?['grammar']),
            const SizedBox(width: 8),
            _tile('Fluency', latestScores['fluency'], prevScores?['fluency']),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _tile('Vocabulary', latestScores['vocabulary'],
                prevScores?['vocabulary']),
            const SizedBox(width: 8),
            _tile(
              'Filler words',
              (latest['filler_words'] as Map?)?['count'],
              (prev?['filler_words'] as Map?)?['count'],
              lowerIsBetter: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _weekDots() {
    final now = DateTime.now();
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 6; i >= 0; i--)
          () {
            final day = now.subtract(Duration(days: i));
            final iso = day.toIso8601String().substring(0, 10);
            final active = _activeDays.contains(iso);
            final isToday = i == 0;
            return Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isToday && active ? Tokens.ringGradient : null,
                    color: isToday && active
                        ? null
                        : active
                            ? Tokens.indigo.withValues(alpha: 0.2)
                            : Tokens.cardHi,
                    border: active && !isToday
                        ? Border.all(
                            color: Tokens.indigo.withValues(alpha: 0.5))
                        : Border.all(color: Tokens.line),
                  ),
                  child: active
                      ? Icon(Icons.check_rounded,
                          size: 16,
                          color: isToday ? Colors.white : Tokens.indigoSoft)
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  letters[day.weekday - 1],
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Tokens.faint,
                  ),
                ),
              ],
            );
          }(),
      ],
    );
  }

  Widget _tile(String label, dynamic value, dynamic prevValue,
      {bool lowerIsBetter = false}) {
    final v = (value as num?)?.toInt();
    final p = (prevValue as num?)?.toInt();
    int? delta;
    if (v != null && p != null) delta = v - p;
    final improved =
        delta == null ? null : (lowerIsBetter ? delta <= 0 : delta >= 0);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Tokens.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Tokens.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${v ?? '—'}',
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w800),
                ),
                if (delta != null && delta != 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${delta > 0 ? '▲' : '▼'}${delta.abs()}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: improved! ? Tokens.mint : Tokens.rose,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: Tokens.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
            color: Tokens.faint,
          ),
        ),
      );
}

/// Single-series trend: faint grid, indigo line, soft area fill, endpoint
/// dot with the latest value labeled.
class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 22.0, padB = 4.0, padT = 12.0;
    final w = size.width - padL, h = size.height - padB - padT;

    final grid = Paint()
      ..color = const Color(0x248B92B4)
      ..strokeWidth = 1;
    final labelStyle = const TextStyle(fontSize: 9, color: Tokens.faint);
    for (final y in [40, 60, 80]) {
      final dy = padT + h * (1 - y / 100);
      canvas.drawLine(Offset(padL, dy), Offset(size.width, dy), grid);
      final tp = TextPainter(
        text: TextSpan(text: '$y', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, dy - tp.height / 2));
    }

    if (values.isEmpty) return;
    Offset point(int i) {
      final x = values.length == 1
          ? padL + w / 2
          : padL + w * i / (values.length - 1);
      final y = padT + h * (1 - (values[i].clamp(0, 100)) / 100);
      return Offset(x, y);
    }

    final line = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(point(i).dx, point(i).dy);
    }

    if (values.length > 1) {
      final area = Path.from(line)
        ..lineTo(point(values.length - 1).dx, padT + h)
        ..lineTo(point(0).dx, padT + h)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x476366F1), Color(0x006366F1)],
          ).createShader(Rect.fromLTWH(0, padT, size.width, h)),
      );
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = Tokens.indigoSoft,
      );
    }

    final last = point(values.length - 1);
    canvas.drawCircle(
        last, 6, Paint()..color = Tokens.card); // surface ring
    canvas.drawCircle(last, 4.5, Paint()..color = Tokens.indigoSoft);
    final tp = TextPainter(
      text: TextSpan(
        text: '${values.last.round()}',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Tokens.ink,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas,
        Offset((last.dx - tp.width).clamp(0, size.width - tp.width),
            (last.dy - 18).clamp(0, size.height)));
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.values != values;
}
