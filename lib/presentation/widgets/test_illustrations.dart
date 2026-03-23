import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── Colores base ───────────────────────────────────────────────────────────────
const _cyan   = Color(0xFF00C9FF);
const _teal   = Color(0xFF4ECDC4);
const _amber  = Color(0xFFF59E0B);
const _green  = Color(0xFF22C55E);
const _purple = Color(0xFF7B2FBE);
const _red    = Color(0xFFEF4444);
const _fig    = Color(0xFFCBD5E1); // cuerpo figura

// ── Helpers ────────────────────────────────────────────────────────────────────

Paint _st(Color c, double w) => Paint()
  ..color = c
  ..strokeWidth = w
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

Paint _fl(Color c) => Paint()..color = c..style = PaintingStyle.fill;

/// Línea de suelo (plataforma simplificada).
void _ground(Canvas canvas, double w, double h, Color color) {
  final y = h * .88;
  canvas.drawLine(Offset(w * .10, y), Offset(w * .90, y), _st(color, 3.0));
  // pequeño efecto de grosor
  canvas.drawLine(Offset(w * .10, y + 3), Offset(w * .90, y + 3),
      _st(color.withValues(alpha: .35), 1.5));
}

/// Figura de palo minimalista:
/// [cx]        centro X
/// [footY]     Y de los pies
/// [h]         altura total de la figura
/// [kneeBend]  0 = piernas rectas, 1 = sentadilla completa
/// [armsUp]    true = brazos arriba, false = brazos al lado
void _stick(Canvas canvas, {
  required double cx,
  required double footY,
  required double figH,
  double kneeBend = 0.0,
  bool armsUp = false,
  Color color = _fig,
  double sw = 2.5,
}) {
  final p = _st(color, sw);
  final headR = figH * .14;
  final torsoBot = footY - figH * (kneeBend > .4 ? .35 : .52);
  final torsoTop = footY - figH * .82;
  final headCy   = torsoTop - headR * 1.1;

  // Cabeza
  canvas.drawCircle(Offset(cx, headCy), headR, _fl(color));

  // Torso
  canvas.drawLine(Offset(cx, torsoTop), Offset(cx, torsoBot), p);

  // Piernas
  if (kneeBend < .3) {
    // Rectas: simple V
    canvas.drawLine(Offset(cx, torsoBot), Offset(cx - figH * .15, footY), p);
    canvas.drawLine(Offset(cx, torsoBot), Offset(cx + figH * .15, footY), p);
  } else {
    // Dobladas: cadera → rodilla (diagonal) → tobillo (vertical)
    final hipY  = torsoBot;
    final kneeY = hipY + figH * .25 * kneeBend;
    for (final s in [-1.0, 1.0]) {
      final hip   = Offset(cx + s * figH * .10, hipY);
      final knee  = Offset(cx + s * figH * .22, kneeY);
      final ankle = Offset(cx + s * figH * .14, footY);
      canvas.drawLine(hip, knee, p);
      canvas.drawLine(knee, ankle, p);
    }
  }

  // Brazos
  final shoulderY = torsoTop + figH * .10;
  if (armsUp) {
    canvas.drawLine(Offset(cx, shoulderY),
        Offset(cx - figH * .26, shoulderY - figH * .30), p);
    canvas.drawLine(Offset(cx, shoulderY),
        Offset(cx + figH * .26, shoulderY - figH * .30), p);
  } else {
    canvas.drawLine(Offset(cx, shoulderY),
        Offset(cx - figH * .26, shoulderY + figH * .20), p);
    canvas.drawLine(Offset(cx, shoulderY),
        Offset(cx + figH * .26, shoulderY + figH * .20), p);
  }
}

/// Flecha con cabeza triangular rellena.
void _arrow(Canvas canvas, Offset from, Offset to, Color color,
    {double sw = 2.2, double hl = 8}) {
  canvas.drawLine(from, to, _st(color, sw));
  final dir  = (to - from) / (to - from).distance;
  final base = to - dir * hl;
  final perp = Offset(-dir.dy, dir.dx) * (hl * .45);
  canvas.drawPath(
    Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(base.dx + perp.dx, base.dy + perp.dy)
      ..lineTo(base.dx - perp.dx, base.dy - perp.dy)
      ..close(),
    _fl(color),
  );
}

// ── Widget wrapper ─────────────────────────────────────────────────────────────
class TestIllustration extends StatelessWidget {
  final CustomPainter painter;
  final double size;
  const TestIllustration({super.key, required this.painter, this.size = 88});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: painter);
}

// ═══════════════════════════════════════════════════════════════════════════════
// CMJ — Countermovement Jump
// Figura en el aire, brazos arriba, flecha de altura
// ═══════════════════════════════════════════════════════════════════════════════
class CmjPainter extends CustomPainter {
  const CmjPainter();

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width, h = sz.height;

    // Suelo
    _ground(canvas, w, h, _cyan.withValues(alpha: .6));

    // Figura en el pico del vuelo (elevada, brazos arriba)
    _stick(canvas,
      cx: w * .42, footY: h * .72, figH: h * .60,
      kneeBend: 0.0, armsUp: true,
      color: _fig, sw: 2.5,
    );

    // Flecha de altura (derecha)
    _arrow(canvas, Offset(w * .74, h * .87), Offset(w * .74, h * .20),
        _cyan, sw: 2.2, hl: 8);

    // Corchete inferior (nivel suelo)
    canvas.drawLine(Offset(w * .68, h * .87), Offset(w * .80, h * .87),
        _st(_cyan.withValues(alpha: .5), 1.5));
    // Corchete superior (altura figura)
    canvas.drawLine(Offset(w * .68, h * .20), Offset(w * .80, h * .20),
        _st(_cyan.withValues(alpha: .5), 1.5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// SJ — Squat Jump
// Figura en cuclillas, flecha vertical hacia arriba
// ═══════════════════════════════════════════════════════════════════════════════
class SjPainter extends CustomPainter {
  const SjPainter();

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width, h = sz.height;

    _ground(canvas, w, h, _teal.withValues(alpha: .6));

    // Figura en cuclillas profunda
    _stick(canvas,
      cx: w * .38, footY: h * .88, figH: h * .64,
      kneeBend: 0.85, armsUp: false,
      color: _fig, sw: 2.5,
    );

    // Flecha vertical de salto
    _arrow(canvas, Offset(w * .72, h * .87), Offset(w * .72, h * .18),
        _teal, sw: 2.5, hl: 9);

    // Símbolo estático "—" bajo la flecha (sin contramovimiento)
    canvas.drawLine(Offset(w * .64, h * .87), Offset(w * .80, h * .87),
        _st(_teal, 2.5));
    canvas.drawLine(Offset(w * .64, h * .92), Offset(w * .80, h * .92),
        _st(_teal.withValues(alpha: .4), 1.5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// DJ — Drop Jump
// Cajón + trayectoria de caída + rebote hacia arriba
// ═══════════════════════════════════════════════════════════════════════════════
class DjPainter extends CustomPainter {
  const DjPainter();

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width, h = sz.height;

    // Suelo principal
    _ground(canvas, w, h, _amber.withValues(alpha: .6));

    // Cajón de caída (izquierda)
    final boxL = w * .08, boxR = w * .34;
    final boxTop = h * .48, boxBot = h * .88;
    final box = RRect.fromLTRBR(boxL, boxTop, boxR, boxBot,
        const Radius.circular(4));
    canvas.drawRRect(box, _fl(const Color(0xFF374151)));
    canvas.drawRRect(box, _st(_amber.withValues(alpha: .7), 1.8));

    // Figura pequeña encima del cajón
    _stick(canvas,
      cx: w * .21, footY: boxTop, figH: h * .38,
      kneeBend: 0.0, armsUp: false,
      color: _fig.withValues(alpha: .7), sw: 2.0,
    );

    // Trayectoria V: caída → rebote
    final mid = Offset(w * .60, h * .87);
    final dropStart = Offset(w * .34, h * .62);
    final riseEnd   = Offset(w * .86, h * .30);

    final path = Path()
      ..moveTo(dropStart.dx, dropStart.dy)
      ..lineTo(mid.dx, mid.dy)
      ..lineTo(riseEnd.dx, riseEnd.dy);
    canvas.drawPath(path, _st(_amber, 2.2));

    // Cabeza de flecha solo en la subida
    _arrow(canvas, Offset(w * .72, h * .58), riseEnd, _amber, sw: 0, hl: 9);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Multi-Salto — Saltos repetidos
// Tres arcos parabólicos sobre línea de suelo
// ═══════════════════════════════════════════════════════════════════════════════
class MultiJumpPainter extends CustomPainter {
  const MultiJumpPainter();

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width, h = sz.height;
    final groundY = h * .78;

    // Línea de suelo
    canvas.drawLine(Offset(w * .05, groundY), Offset(w * .95, groundY),
        _st(_purple.withValues(alpha: .6), 3.0));

    // Tres arcos parabólicos (alturas crecientes → decrecientes → RSI)
    final arcs = [
      (x0: w*.06, x1: w*.38, peak: h*.20),
      (x0: w*.38, x1: w*.66, peak: h*.12),
      (x0: w*.66, x1: w*.94, peak: h*.18),
    ];

    for (int i = 0; i < arcs.length; i++) {
      final a = arcs[i];
      final color = i == 1 ? _cyan : _purple;
      final path  = Path()..moveTo(a.x0, groundY);
      final cx1   = (a.x0 + a.x1) / 2 - (a.x1 - a.x0) * .15;
      final cx2   = (a.x0 + a.x1) / 2 + (a.x1 - a.x0) * .15;
      path.cubicTo(cx1, a.peak, cx2, a.peak, a.x1, groundY);
      canvas.drawPath(path, _st(color, i == 1 ? 2.8 : 2.0));

      // Punto de despegue y aterrizaje
      canvas.drawCircle(Offset(a.x0, groundY), 3,
          _fl(color.withValues(alpha: .8)));
      canvas.drawCircle(Offset(a.x1, groundY), 3,
          _fl(color.withValues(alpha: .8)));
    }

    // Flechas en los picos
    for (final a in arcs) {
      final mx = (a.x0 + a.x1) / 2;
      canvas.drawLine(Offset(mx, a.peak + 10), Offset(mx, a.peak + 2),
          _st(_green, 1.8));
      _arrow(canvas, Offset(mx, a.peak + 2), Offset(mx, a.peak - 4),
          _green, sw: 0, hl: 5);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// CoP — Centro de Presiones / Equilibrio
// Dos huellas de pie + trayectoria oscilante + elipse
// ═══════════════════════════════════════════════════════════════════════════════
class CopPainter extends CustomPainter {
  const CopPainter();

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width, h = sz.height;
    final cx = w / 2, cy = h * .52;

    // Plataforma (rectángulo de fondo sutil)
    canvas.drawRRect(
      RRect.fromLTRBR(w*.06, h*.08, w*.94, h*.92, const Radius.circular(8)),
      _fl(const Color(0xFF1C2430)),
    );
    canvas.drawRRect(
      RRect.fromLTRBR(w*.06, h*.08, w*.94, h*.92, const Radius.circular(8)),
      _st(_green.withValues(alpha: .25), 1.5),
    );

    // Pie izquierdo
    _drawFoot(canvas, cx - w * .16, cy, w * .22, h * .50, flip: false);
    // Pie derecho
    _drawFoot(canvas, cx + w * .16, cy, w * .22, h * .50, flip: true);

    // Elipse 95%
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - h * .02),
          width: w * .32, height: h * .24),
      Paint()
        ..color = _green.withValues(alpha: .15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - h * .02),
          width: w * .32, height: h * .24),
      _st(_green, 1.5),
    );

    // Trayectoria CoP (línea corta serpenteante)
    final pts = _traj(cx, cy - h * .02, w * .08, h * .06);
    final tp = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < pts.length; i++) tp.lineTo(pts[i].dx, pts[i].dy);
    canvas.drawPath(tp, _st(_cyan, 1.8));
    canvas.drawCircle(pts.last, 3.5, _fl(_cyan));
  }

  List<Offset> _traj(double cx, double cy, double rx, double ry) {
    final r = math.Random(7);
    double x = cx, y = cy;
    return List.generate(20, (_) {
      x = (x + (r.nextDouble() - .5) * rx * .4).clamp(cx - rx, cx + rx);
      y = (y + (r.nextDouble() - .5) * ry * .4).clamp(cy - ry, cy + ry);
      return Offset(x, y);
    });
  }

  void _drawFoot(Canvas canvas, double cx, double cy,
      double fw, double fh, {required bool flip}) {
    final s = flip ? -1.0 : 1.0;
    // Talón
    final heel   = Offset(cx, cy + fh * .25);
    // Arco / empeine
    final arch   = Offset(cx + s * fw * .15, cy);
    // Bola del pie
    final ball   = Offset(cx + s * fw * .28, cy - fh * .15);
    // Dedo gordo
    final bigToe = Offset(cx + s * fw * .26, cy - fh * .32);

    final path = Path()
      ..moveTo(heel.dx, heel.dy)
      ..quadraticBezierTo(
          cx - s * fw * .22, cy + fh * .22, arch.dx, arch.dy)
      ..quadraticBezierTo(arch.dx, cy - fh * .05, ball.dx, ball.dy)
      ..quadraticBezierTo(
          cx + s * fw * .30, cy - fh * .24, bigToe.dx, bigToe.dy)
      ..quadraticBezierTo(
          cx + s * fw * .18, cy - fh * .38, cx, cy - fh * .30)
      ..quadraticBezierTo(
          cx - s * fw * .08, cy + fh * .05, heel.dx, heel.dy)
      ..close();

    canvas.drawPath(path, _fl(_fig.withValues(alpha: .18)));
    canvas.drawPath(path, _st(_fig.withValues(alpha: .55), 1.5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// IMTP — Isometric Mid-Thigh Pull
// Figura tirando de barra, gran flecha de fuerza vertical
// ═══════════════════════════════════════════════════════════════════════════════
class ImtpPainter extends CustomPainter {
  const ImtpPainter();

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width, h = sz.height;

    // Suelo
    _ground(canvas, w, h, _red.withValues(alpha: .5));

    // Figura (leve flexión de rodillas, brazos hacia abajo/barra)
    _stick(canvas,
      cx: w * .38, footY: h * .88, figH: h * .64,
      kneeBend: 0.35, armsUp: false,
      color: _fig, sw: 2.5,
    );

    // Barra horizontal (a la altura del muslo medio)
    final barY = h * .52;
    canvas.drawLine(Offset(w * .10, barY), Offset(w * .68, barY),
        _st(_red, 4.0));
    // Muescas de la barra
    for (final bx in [w * .16, w * .62]) {
      canvas.drawRect(
        Rect.fromCenter(center: Offset(bx, barY), width: 7, height: 10),
        _fl(_red.withValues(alpha: .6)),
      );
    }

    // Cadenas de anclaje al suelo (líneas verticales cortas)
    for (final bx in [w * .20, w * .56]) {
      canvas.drawLine(Offset(bx, barY), Offset(bx, h * .88),
          _st(_red.withValues(alpha: .4), 1.5));
    }

    // Flecha de fuerza GRANDE (F↑)
    _arrow(canvas, Offset(w * .82, h * .87), Offset(w * .82, h * .14),
        _red, sw: 3.0, hl: 11);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
