import 'package:flutter/material.dart';

// ── Colores base (consistentes con app_colors.dart) ───────────────────────
const _cyan    = Color(0xFF00C9FF);
const _green   = Color(0xFF22C55E);
const _plat    = Color(0xFF374151); // plataforma
const _dark    = Color(0xFF1F2937); // sombra plataforma
const _white   = Color(0xFFFFFFFF);

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET HELPER — envuelve cualquier painter en un widget con tamaño fijo
// ═══════════════════════════════════════════════════════════════════════════
class TestIllustration extends StatelessWidget {
  final CustomPainter painter;
  final double size;
  const TestIllustration({super.key, required this.painter, this.size = 88});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: painter,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// PAINTERS POR TEST
// ═══════════════════════════════════════════════════════════════════════════

// ── 1. CMJ — Salto con Contramovimiento ───────────────────────────────────
/// Figura en el aire, brazos alzados, piernas ligeramente flexionadas.
/// Flecha verde hacia arriba.
class CmjPainter extends CustomPainter {
  const CmjPainter();

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width, h = sz.height;
    _drawPlatform(canvas, w, h);

    final fig = _figurePaint(w);
    final fill = Paint()..color = _cyan..style = PaintingStyle.fill;

    // Cabeza
    canvas.drawCircle(Offset(w * .45, h * .13), w * .075, fill);
    // Torso
    canvas.drawLine(Offset(w*.45, h*.21), Offset(w*.45, h*.52), fig);
    // Brazo izquierdo arriba
    canvas.drawLine(Offset(w*.43, h*.28), Offset(w*.26, h*.12), fig);
    // Brazo derecho arriba
    canvas.drawLine(Offset(w*.47, h*.28), Offset(w*.63, h*.10), fig);
    // Pierna izquierda (rodilla doblada en el aire)
    canvas.drawLine(Offset(w*.43, h*.52), Offset(w*.34, h*.68), fig);
    canvas.drawLine(Offset(w*.34, h*.68), Offset(w*.38, h*.80), fig);
    // Pierna derecha
    canvas.drawLine(Offset(w*.47, h*.52), Offset(w*.56, h*.68), fig);
    canvas.drawLine(Offset(w*.56, h*.68), Offset(w*.52, h*.80), fig);

    // Flecha verde ↑
    _drawArrowUp(canvas, w, h, dx: .82);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── 2. SJ — Squat Jump ────────────────────────────────────────────────────
/// Figura en cuclillas (rodillas ~90°), manos en caderas, flecha ↑.
class SjPainter extends CustomPainter {
  const SjPainter();

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width, h = sz.height;
    _drawPlatform(canvas, w, h);

    final fig = _figurePaint(w);
    final fill = Paint()..color = _cyan..style = PaintingStyle.fill;

    // Figura en sentadilla
    canvas.drawCircle(Offset(w * .44, h * .22), w * .075, fill);
    canvas.drawLine(Offset(w*.44, h*.30), Offset(w*.44, h*.56), fig);
    // Brazos en caderas (horizontales)
    canvas.drawLine(Offset(w*.42, h*.36), Offset(w*.27, h*.38), fig);
    canvas.drawLine(Offset(w*.46, h*.36), Offset(w*.61, h*.38), fig);
    // Muslo izquierdo (hacia abajo y afuera — sentadilla profunda)
    canvas.drawLine(Offset(w*.42, h*.56), Offset(w*.30, h*.74), fig);
    // Espinilla izquierda (hacia arriba → vertical)
    canvas.drawLine(Offset(w*.30, h*.74), Offset(w*.33, h*.85), fig);
    // Muslo derecho
    canvas.drawLine(Offset(w*.46, h*.56), Offset(w*.58, h*.74), fig);
    // Espinilla derecha
    canvas.drawLine(Offset(w*.58, h*.74), Offset(w*.55, h*.85), fig);

    _drawArrowUp(canvas, w, h, dx: .82);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── 3. Drop Jump ──────────────────────────────────────────────────────────
/// Cajón a la izquierda, figura cayendo sobre plataforma, flecha ↓ luego ↑.
class DjPainter extends CustomPainter {
  const DjPainter();

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width, h = sz.height;
    _drawPlatform(canvas, w, h);

    // Cajón elevado (izquierda)
    final boxPaint = Paint()..color = _plat..style = PaintingStyle.fill;
    final boxBorder = Paint()..color = _dark..style = PaintingStyle.stroke..strokeWidth = 1.5;
    final boxRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w*.04, h*.54, w*.20, h*.30),
      const Radius.circular(3),
    );
    canvas.drawRRect(boxRect, boxPaint);
    canvas.drawRRect(boxRect, boxBorder);
    // Líneas del cajón
    canvas.drawLine(Offset(w*.04, h*.64), Offset(w*.24, h*.64),
        Paint()..color = _dark..strokeWidth = 1.2);

    final fig = _figurePaint(w * .85);
    final fill = Paint()..color = _cyan..style = PaintingStyle.fill;

    // Figura parada en el cajón (arriba)
    canvas.drawCircle(Offset(w * .14, h * .29), w * .065, fill);
    canvas.drawLine(Offset(w*.14, h*.36), Offset(w*.14, h*.52), fig);
    canvas.drawLine(Offset(w*.12, h*.42), Offset(w*.05, h*.44), fig);
    canvas.drawLine(Offset(w*.16, h*.42), Offset(w*.23, h*.44), fig);
    canvas.drawLine(Offset(w*.12, h*.52), Offset(w*.09, h*.54), fig);
    canvas.drawLine(Offset(w*.16, h*.52), Offset(w*.19, h*.54), fig);

    // Flecha ↓ desde cajón a plataforma
    _drawArrowVertical(canvas, w, h, dx: .34, fromY: .48, toY: .77, up: false);

    // Figura aterrizando en plataforma (posición de impacto)
    canvas.drawCircle(Offset(w * .56, h * .32), w * .065, fill);
    canvas.drawLine(Offset(w*.56, h*.39), Offset(w*.56, h*.58), fig);
    canvas.drawLine(Offset(w*.54, h*.45), Offset(w*.44, h*.40), fig);
    canvas.drawLine(Offset(w*.58, h*.45), Offset(w*.68, h*.40), fig);
    // Piernas dobladas (impacto)
    canvas.drawLine(Offset(w*.53, h*.58), Offset(w*.44, h*.72), fig);
    canvas.drawLine(Offset(w*.44, h*.72), Offset(w*.47, h*.85), fig);
    canvas.drawLine(Offset(w*.59, h*.58), Offset(w*.68, h*.72), fig);
    canvas.drawLine(Offset(w*.68, h*.72), Offset(w*.65, h*.85), fig);

    // Flecha ↑ rebote
    _drawArrowVertical(canvas, w, h, dx: .84, fromY: .78, toY: .28, up: true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── 4. Multi-Salto ────────────────────────────────────────────────────────
/// Tres arcos parabólicos encima de la plataforma con puntos de contacto.
class MultiJumpPainter extends CustomPainter {
  const MultiJumpPainter();

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width, h = sz.height;
    _drawPlatform(canvas, w, h);

    final arcPaint = Paint()
      ..color = _cyan
      ..strokeWidth = w * .045
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()..color = _green..style = PaintingStyle.fill;

    // 4 arcos parabólicos — ancho igual, alturas ligeramente diferentes
    final contactX = [w*.12, w*.32, w*.52, w*.72, w*.88];
    final peakH    = [h*.35, h*.28, h*.32, h*.38]; // distintas alturas
    final baseY    = h * .86;

    for (int i = 0; i < 4; i++) {
      final x1 = contactX[i];
      final x2 = contactX[i + 1];
      final cx = (x1 + x2) / 2;
      final path = Path();
      path.moveTo(x1, baseY);
      path.quadraticBezierTo(cx, peakH[i], x2, baseY);
      canvas.drawPath(path, arcPaint);

      // Puntos de contacto
      canvas.drawCircle(Offset(x1, baseY), w * .028, dotPaint);
    }
    canvas.drawCircle(Offset(contactX.last, baseY), w * .028, dotPaint);

    // Pequeña figura en el arco central (pico)
    final mid = (contactX[1] + contactX[2]) / 2;
    final fill = Paint()..color = _cyan..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(mid, peakH[1] - w * .07), w * .055, fill);
    final fig = _figurePaint(w * .80);
    canvas.drawLine(Offset(mid, peakH[1] - w*.01), Offset(mid, peakH[1] + w*.12), fig);
    canvas.drawLine(Offset(mid, peakH[1] + w*.05), Offset(mid - w*.08, peakH[1]), fig);
    canvas.drawLine(Offset(mid, peakH[1] + w*.05), Offset(mid + w*.08, peakH[1]), fig);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── 5. CoP / Equilibrio ───────────────────────────────────────────────────
/// Figura de pie, postura neutra, trayectoria del CoP bajo la plataforma.
class CopPainter extends CustomPainter {
  const CopPainter();

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width, h = sz.height;
    _drawPlatform(canvas, w, h);

    final fig = _figurePaint(w);
    final fill = Paint()..color = _cyan..style = PaintingStyle.fill;

    // Figura de pie (postura neutra)
    canvas.drawCircle(Offset(w * .50, h * .12), w * .075, fill);
    canvas.drawLine(Offset(w*.50, h*.20), Offset(w*.50, h*.55), fig);
    // Brazos ligeramente abiertos (balance natural)
    canvas.drawLine(Offset(w*.48, h*.30), Offset(w*.32, h*.44), fig);
    canvas.drawLine(Offset(w*.52, h*.30), Offset(w*.68, h*.44), fig);
    // Piernas verticales
    canvas.drawLine(Offset(w*.47, h*.55), Offset(w*.42, h*.85), fig);
    canvas.drawLine(Offset(w*.53, h*.55), Offset(w*.58, h*.85), fig);

    // Trayectoria CoP (bajo plataforma) — curva tipo oscilación
    final copPaint = Paint()
      ..color = _green.withOpacity(.85)
      ..strokeWidth = w * .030
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(w*.20, h*.94);
    // Serie de ondas suaves representando el sway
    for (int i = 0; i < 5; i++) {
      final x1 = w*.20 + i * w*.13;
      final x2 = x1 + w*.065;
      final x3 = x2 + w*.065;
      final sign = (i % 2 == 0) ? -1 : 1;
      path.quadraticBezierTo(x2, h*.94 + sign * h*.025, x3, h*.94);
    }
    canvas.drawPath(path, copPaint);

    // Punto CoP actual
    canvas.drawCircle(Offset(w*.85, h*.94), w*.028,
        Paint()..color = _green..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── 6. IMTP — Tracción Isométrica ─────────────────────────────────────────
/// Figura en posición de "power" tirando de una barra fija, sin movimiento.
class ImtpPainter extends CustomPainter {
  const ImtpPainter();

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width, h = sz.height;
    _drawPlatform(canvas, w, h);

    // Estructura del rack (barra fija)
    final rackPaint = Paint()
      ..color = _plat
      ..strokeWidth = w * .045
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    // Postes verticales del rack
    canvas.drawLine(Offset(w*.12, h*.12), Offset(w*.12, h*.86), rackPaint);
    canvas.drawLine(Offset(w*.88, h*.12), Offset(w*.88, h*.86), rackPaint);
    // Barra horizontal (donde el atleta jala)
    final barPaint = Paint()
      ..color = _white.withOpacity(.85)
      ..strokeWidth = w * .055
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w*.12, h*.46), Offset(w*.88, h*.46), barPaint);
    // Clips de barra
    final clipPaint = Paint()..color = _plat..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w*.22, h*.46), w*.048, clipPaint);
    canvas.drawCircle(Offset(w*.78, h*.46), w*.048, clipPaint);

    // Figura en posición IMTP (media sentadilla, espalda recta, agarre de barra)
    final fig = _figurePaint(w);
    final fill = Paint()..color = _cyan..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(w * .50, h * .20), w * .075, fill);
    // Tronco inclinado levemente hacia delante
    canvas.drawLine(Offset(w*.50, h*.28), Offset(w*.50, h*.58), fig);
    // Brazos hacia la barra (tirando hacia arriba)
    canvas.drawLine(Offset(w*.47, h*.36), Offset(w*.30, h*.46), fig);
    canvas.drawLine(Offset(w*.53, h*.36), Offset(w*.70, h*.46), fig);
    // Piernas en media sentadilla (~135°)
    canvas.drawLine(Offset(w*.46, h*.58), Offset(w*.38, h*.74), fig);
    canvas.drawLine(Offset(w*.38, h*.74), Offset(w*.40, h*.86), fig);
    canvas.drawLine(Offset(w*.54, h*.58), Offset(w*.62, h*.74), fig);
    canvas.drawLine(Offset(w*.62, h*.74), Offset(w*.60, h*.86), fig);

    // Flechas de fuerza (bidireccionales — isométrico)
    _drawForceIndicator(canvas, w, h);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS PRIVADOS
// ═══════════════════════════════════════════════════════════════════════════

Paint _figurePaint(double refW) => Paint()
  ..color = _cyan
  ..strokeWidth = refW * 0.075
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..style = PaintingStyle.stroke;

/// Plataforma de fuerza en la parte inferior.
void _drawPlatform(Canvas canvas, double w, double h) {
  // Sombra
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(w * .08, h * .88, w * .84, h * .095),
      const Radius.circular(5),
    ),
    Paint()..color = _dark..style = PaintingStyle.fill,
  );
  // Cuerpo de la plataforma
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(w * .06, h * .855, w * .88, h * .09),
      const Radius.circular(5),
    ),
    Paint()..color = _plat..style = PaintingStyle.fill,
  );
  // Línea superior (detalle reflejo)
  canvas.drawLine(
    Offset(w * .10, h * .862),
    Offset(w * .90, h * .862),
    Paint()
      ..color = _white.withOpacity(.12)
      ..strokeWidth = 1.5,
  );
}

/// Flecha vertical hacia arriba, en posición dx (fracción del ancho).
void _drawArrowUp(Canvas canvas, double w, double h,
    {double dx = 0.82, double fromY = 0.78, double toY = 0.22}) {
  final paint = Paint()
    ..color = _green
    ..strokeWidth = w * .042
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  canvas.drawLine(Offset(w * dx, h * fromY), Offset(w * dx, h * toY), paint);

  // Punta de la flecha
  final path = Path()
    ..moveTo(w * (dx - .08), h * (toY + .14))
    ..lineTo(w * dx, h * toY)
    ..lineTo(w * (dx + .08), h * (toY + .14));
  canvas.drawPath(path, paint);
}

/// Flecha vertical configurable (up o down).
void _drawArrowVertical(Canvas canvas, double w, double h,
    {required double dx,
    required double fromY,
    required double toY,
    required bool up}) {
  final paint = Paint()
    ..color = _green
    ..strokeWidth = w * .038
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  canvas.drawLine(Offset(w * dx, h * fromY), Offset(w * dx, h * toY), paint);

  final tipY = up ? toY : toY;
  final path = Path()
    ..moveTo(w * (dx - .065), h * (tipY + (up ? .13 : -.13)))
    ..lineTo(w * dx, h * tipY)
    ..lineTo(w * (dx + .065), h * (tipY + (up ? .13 : -.13)));
  canvas.drawPath(path, paint);
}

/// Indicador de fuerza isométrica: flecha ↑ (fuerza atleta) + ↓ tenue (reacción barra).
void _drawForceIndicator(Canvas canvas, double w, double h) {
  final paint = Paint()
    ..color = _green.withOpacity(.85)
    ..strokeWidth = w * .038
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  // Flecha hacia arriba
  canvas.drawLine(Offset(w * .92, h * .56), Offset(w * .92, h * .36), paint);
  final upHead = Path()
    ..moveTo(w * .86, h * .46)
    ..lineTo(w * .92, h * .36)
    ..lineTo(w * .98, h * .46);
  canvas.drawPath(upHead, paint);

  // Flecha hacia abajo (tenue — reacción)
  final paintDim = Paint()
    ..color = _green.withOpacity(.28)
    ..strokeWidth = w * .038
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  canvas.drawLine(Offset(w * .92, h * .36), Offset(w * .92, h * .56), paintDim);
  final dnHead = Path()
    ..moveTo(w * .86, h * .46)
    ..lineTo(w * .92, h * .56)
    ..lineTo(w * .98, h * .46);
  canvas.drawPath(dnHead, paintDim);
}
