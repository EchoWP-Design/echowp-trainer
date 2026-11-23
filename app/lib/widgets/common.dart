import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(title.toUpperCase(),
                    style: const TextStyle(
                        color: echoYellow, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.1)),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// Kreisanzeige für den Bereitschafts-Score.
class ScoreRing extends StatelessWidget {
  final int? score;
  final Color color;
  final double size;
  const ScoreRing({super.key, required this.score, required this.color, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter((score ?? 0) / 100, color),
        child: Center(
          child: Text(score?.toString() ?? '–',
              style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w900, color: Colors.white)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  _RingPainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final bg = Paint()
      ..color = echoSurface2
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, bg);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value.clamp(0, 1), false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}

/// Balkenverlauf (z. B. Score der letzten 14 Tage).
class TrendBars extends StatelessWidget {
  final List<(String, int?)> points;
  const TrendBars({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final p in points)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (p.$2 != null) Text('${p.$2}', style: const TextStyle(fontSize: 9, color: echoMuted)),
                    const SizedBox(height: 2),
                    Container(
                      height: p.$2 == null ? 3 : 56 * p.$2! / 100 + 3,
                      decoration: BoxDecoration(
                        color: p.$2 == null ? echoSurface2 : levelColors[levelOf(p.$2!)],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(p.$1.substring(8), style: const TextStyle(fontSize: 9, color: echoMuted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String levelOf(int score) => score >= 80
    ? 'push'
    : score >= 65
        ? 'normal'
        : score >= 50
            ? 'locker'
            : 'recovery';

class StatTile extends StatelessWidget {
  final String label, value;
  final String? unit;
  const StatTile(this.label, this.value, {super.key, this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: echoSurface2, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: echoMuted, fontSize: 11), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              if (unit != null) TextSpan(text: ' $unit', style: const TextStyle(color: echoMuted, fontSize: 12)),
            ]),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Raster aus Kacheln, auf schmalen Handys zwei, sonst drei Spalten.
class TileGrid extends StatelessWidget {
  final List<Widget> children;
  const TileGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 330 ? 2 : 3;
      final w = (c.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

String fmtNum(num? v, {int digits = 0}) {
  if (v == null) return '–';
  return v.toStringAsFixed(digits).replaceAll('.', ',');
}

void showSnack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
