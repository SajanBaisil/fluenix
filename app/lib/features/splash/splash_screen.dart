import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Animated boot splash (design: splash screen in Fluenix App.dc.html).
/// Ink background, clay glow, the live waveform, wordmark and tagline,
/// with a 2.2s loader. Renders over [child] and fades away when the loader
/// completes; tapping skips straight in.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});
  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with TickerProviderStateMixin {
  late final AnimationController _boot = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  late final AnimationController _wf = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _boot.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    _boot.forward();
  }

  void _finish() {
    if (!_done && mounted) setState(() => _done = true);
  }

  @override
  void dispose() {
    _boot.dispose();
    _wf.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        IgnorePointer(
          ignoring: _done,
          child: AnimatedOpacity(
            opacity: _done ? 0 : 1,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOut,
            child: _splash(),
          ),
        ),
      ],
    );
  }

  Widget _splash() {
    return GestureDetector(
      onTap: _finish,
      child: Container(
        color: Tokens.ink,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Clay glow behind the mark.
            Align(
              alignment: const Alignment(0, -0.15),
              child: Container(
                width: 460,
                height: 460,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x66C9502B), Colors.transparent],
                    stops: [0, 0.66],
                  ),
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _rise(
                  0,
                  AnimatedBuilder(
                    animation: _wf,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (i, h) in const [
                          30.0, 62.0, 104.0, 62.0, 38.0,
                        ].indexed)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4.5),
                            child: _bar(i, h),
                          ),
                      ],
                    ),
                  ),
                  height: 104,
                ),
                const SizedBox(height: 38),
                _rise(
                  0.12,
                  Text('Fluenix',
                      style: Type.display(46, color: Tokens.cream)),
                ),
                const SizedBox(height: 16),
                _rise(
                  0.24,
                  Text(
                    'SPEAK ENGLISH ON A CALL',
                    style: Type.mono(10, color: Tokens.cream45, ls: 2.2),
                  ),
                ),
              ],
            ),
            // Loader + hint pinned to the bottom.
            Positioned(
              left: 0,
              right: 0,
              bottom: 52,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      width: 104,
                      height: 3,
                      child: AnimatedBuilder(
                        animation: _boot,
                        builder: (context, _) => LinearProgressIndicator(
                          value: Curves.easeOut.transform(_boot.value),
                          backgroundColor: Tokens.cream12,
                          color: Tokens.clay,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'TAP TO CONTINUE',
                    style: Type.mono(10, color: const Color(0x59F6F1E8),
                        ls: 1.8),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Design's riseIn: opacity 0→1, translateY 8→0, .6s eased, staggered.
  Widget _rise(double delay, Widget child, {double? height}) {
    final anim = CurvedAnimation(
      parent: _boot,
      curve: Interval(delay * 0.45, delay * 0.45 + 0.27, curve: Curves.ease),
    );
    final wrapped = AnimatedBuilder(
      animation: anim,
      builder: (context, _) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - anim.value)),
          child: child,
        ),
      ),
    );
    return height == null ? wrapped : SizedBox(height: height, child: wrapped);
  }

  Widget _bar(int i, double maxH) {
    // Same motion as the in-call waveform: scaleY .18→1→.18, staggered.
    final phase = (_wf.value + i * 0.108) % 1.0;
    final scale = 0.18 + 0.82 * math.sin(phase * math.pi);
    const colors = [
      Color(0xFFF0C9A8),
      Color(0xFFE8A06F),
      Color(0xFFC9502B),
      Color(0xFFE8A06F),
      Color(0xFFF0C9A8),
    ];
    return Container(
      width: 9,
      height: maxH * scale,
      decoration: BoxDecoration(
        color: colors[i],
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}
