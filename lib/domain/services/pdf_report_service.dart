import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../entities/athlete.dart';
import '../entities/test_result.dart';

/// Generates a professional A4 PDF report for any [TestResult] and opens
/// the system share/print sheet via the `printing` package.
class PdfReportService {
  // ── Color palette (light background — optimised for printing) ─────────────
  static const _cNavy    = PdfColor(0.051, 0.106, 0.180); // #0D1B2E
  static const _cCyan    = PdfColor(0.000, 0.788, 1.000); // #00C9FF
  static const _cWhite   = PdfColor(1.000, 1.000, 1.000);
  static const _cSurface = PdfColor(0.960, 0.968, 0.980); // #F5F7FA
  static const _cTextD   = PdfColor(0.100, 0.110, 0.150);
  static const _cTextM   = PdfColor(0.400, 0.450, 0.520);
  static const _cSuccess = PdfColor(0.133, 0.773, 0.367); // #22C55E
  static const _cDanger  = PdfColor(0.937, 0.267, 0.267); // #EF4444
  static const _cBorder  = PdfColor(0.878, 0.898, 0.922);
  // Lighter variants for the right half of symmetry bar
  static const _cSuccessL = PdfColor(0.133, 0.773, 0.367, 0.50);
  static const _cDangerL  = PdfColor(0.937, 0.267, 0.267, 0.45);

  // ── Public API ────────────────────────────────────────────────────────────

  /// Generates a PDF and opens the system share sheet.
  ///
  /// Pass [athlete] to include name and sport in the header.
  /// Pass [rawForceN] + [rawTimeS] to include a force-time curve above the
  /// metrics tables (typically from [TestStateNotifier.lastForceN/lastTimeS]).
  static Future<void> generateAndShare({
    required TestResult result,
    Athlete? athlete,
    List<double>? rawForceN,
    List<double>? rawTimeS,
  }) async {
    final doc = pw.Document(
      author: 'InertiaX',
      title: '${result.testType.displayName} — ${athlete?.name ?? "Atleta"}',
    );

    // Validated curve data (must be same length and non-trivial).
    final List<double>? fCurve = (rawForceN != null &&
            rawTimeS != null &&
            rawForceN.length == rawTimeS.length &&
            rawForceN.length > 10)
        ? rawForceN
        : null;
    final List<double>? tCurve = fCurve != null ? rawTimeS : null;

    // Body-weight reference for the BW line in the chart.
    double? bwRef;
    if (result is JumpResult)  bwRef = result.bodyWeightN;
    if (result is ImtpResult)  bwRef = result.peakForceBW > 0 ? result.peakForceN / result.peakForceBW : null;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 44, vertical: 40),
        header: (_) => _buildHeader(result, athlete),
        footer: (_) => _buildFooter(result),
        build:  (_) => _buildBody(result, fCurve, tCurve, bwRef),
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: _filename(result));
  }

  // ── Header / Footer ───────────────────────────────────────────────────────

  static pw.Widget _buildHeader(TestResult r, Athlete? a) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'InertiaX',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: _cNavy,
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  _fmtDate(r.computedAt),
                  style: pw.TextStyle(fontSize: 9, color: _cTextM),
                ),
                if (a != null) ...[
                  pw.Text(
                    a.name,
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: _cTextD,
                    ),
                  ),
                  if (a.sport != null && a.sport!.isNotEmpty)
                    pw.Text(
                      a.sport!,
                      style: pw.TextStyle(fontSize: 9, color: _cTextM),
                    ),
                ],
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Divider(color: _cCyan, thickness: 2),
        pw.SizedBox(height: 4),
        pw.Text(
          r.testType.displayName.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: _cNavy,
            letterSpacing: 2,
          ),
        ),
        pw.SizedBox(height: 10),
      ],
    );
  }

  static pw.Widget _buildFooter(TestResult r) {
    return pw.Column(
      children: [
        pw.Divider(color: _cBorder, thickness: 0.5),
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'InertiaX  |  Plataformas: ${r.platformCount}',
              style: pw.TextStyle(fontSize: 8, color: _cTextM),
            ),
            pw.Text(
              'Generado automaticamente por InertiaX',
              style: pw.TextStyle(fontSize: 8, color: _cTextM),
            ),
          ],
        ),
      ],
    );
  }

  // ── Body dispatcher ───────────────────────────────────────────────────────

  static List<pw.Widget> _buildBody(
    TestResult r,
    List<double>? forceN,
    List<double>? timeS,
    double? bwN,
  ) =>
      switch (r) {
        DropJumpResult res  => _djBody(res,   forceN, timeS, bwN),
        JumpResult res      => _jumpBody(res, forceN, timeS, bwN),
        CoPResult res       => _copBody(res),
        ImtpResult res      => _imtpBody(res, forceN, timeS, bwN),
        MultiJumpResult res => _multiBody(res),
      };

  // ── Jump (CMJ / SJ) ───────────────────────────────────────────────────────

  static List<pw.Widget> _jumpBody(
    JumpResult r,
    List<double>? forceN,
    List<double>? timeS,
    double? bwN,
  ) => [
        _hero('ALTURA DE SALTO', r.jumpHeightCm.toStringAsFixed(1), 'cm'),
        if (forceN != null && timeS != null) ...[
          pw.SizedBox(height: 10),
          _forceCurve(forceN, timeS, bwN),
        ],
        pw.SizedBox(height: 16),
        _section('RENDIMIENTO'),
        _table([
          _e('Altura de salto',         '${r.jumpHeightCm.toStringAsFixed(1)} cm'),
          _e('Tiempo de vuelo',         '${r.flightTimeMs.toStringAsFixed(0)} ms'),
          _e('Fuerza pico',             '${r.peakForceN.toStringAsFixed(0)} N'),
          _e('Fuerza media',            '${r.meanForceN.toStringAsFixed(0)} N'),
          _e('Potencia pico (Sayers)',  '${r.peakPowerSayersW.toStringAsFixed(0)} W'),
          _e('Potencia pico (impulso)', '${r.peakPowerImpulseW.toStringAsFixed(0)} W'),
        ]),
        pw.SizedBox(height: 12),
        _section('TASA DE DESARROLLO DE FUERZA (RFD)'),
        _table([
          _e('RFD 50 ms',             '${(r.rfdAt50ms  / 1000).toStringAsFixed(1)} kN/s'),
          _e('RFD 100 ms',            '${(r.rfdAt100ms / 1000).toStringAsFixed(1)} kN/s'),
          _e('RFD 200 ms',            '${(r.rfdAt200ms / 1000).toStringAsFixed(1)} kN/s'),
          _e('T. hasta fuerza pico',  '${r.timeToPeakForceMs.toStringAsFixed(0)} ms'),
        ]),
        pw.SizedBox(height: 12),
        _section('IMPULSO Y FASES'),
        _table([
          _e('Impulso propulsivo', '${r.propulsiveImpulseNs.toStringAsFixed(1)} N*s'),
          _e('Impulso de frenado', '${r.brakingImpulseNs.toStringAsFixed(1)} N*s'),
          _e('Fase excentrica',    '${r.eccentricDurationMs.toStringAsFixed(0)} ms'),
          _e('Fase concentrica',   '${r.concentricDurationMs.toStringAsFixed(0)} ms'),
          _e('Fuerza de despegue', '${r.takeoffForceN.toStringAsFixed(0)} N'),
          _e('Peso corporal',      '${(r.bodyWeightN / 9.81).toStringAsFixed(1)} kg'),
        ]),
        pw.SizedBox(height: 12),
        _symSection(r.symmetry),
      ];

  // ── Drop Jump ─────────────────────────────────────────────────────────────

  static List<pw.Widget> _djBody(
    DropJumpResult r,
    List<double>? forceN,
    List<double>? timeS,
    double? bwN,
  ) => [
        ..._jumpBody(r, forceN, timeS, bwN),
        pw.SizedBox(height: 12),
        _section('DROP JUMP'),
        _table([
          _e('Tiempo de contacto', '${r.contactTimeMs.toStringAsFixed(0)} ms'),
          _e('RSImod',              r.rsiMod.toStringAsFixed(3)),
        ]),
      ];

  // ── CoP / Balance ─────────────────────────────────────────────────────────

  static List<pw.Widget> _copBody(CoPResult r) => [
        _hero('AREA ELIPSE 95%', r.areaEllipseMm2.toStringAsFixed(0), 'mm2'),
        pw.SizedBox(height: 16),
        _section('CONDICIONES'),
        _table([
          _e('Condicion',
              r.condition == 'OA' ? 'Ojos abiertos' : 'Ojos cerrados'),
          _e('Postura', r.stance == 'bipedal'
              ? 'Bipodal'
              : r.stance == 'left'
                  ? 'Unipodal izquierdo'
                  : 'Unipodal derecho'),
          _e('Duracion', '${r.testDurationS.toStringAsFixed(1)} s'),
        ]),
        pw.SizedBox(height: 12),
        _section('ESTABILIDAD'),
        _table([
          _e('Area elipse 95%',    '${r.areaEllipseMm2.toStringAsFixed(0)} mm2'),
          _e('Long. trayectoria',  '${r.pathLengthMm.toStringAsFixed(0)} mm'),
          _e('Velocidad media',    '${r.meanVelocityMmS.toStringAsFixed(1)} mm/s'),
          _e('Rango medio-lat.',   '${r.rangeMLMm.toStringAsFixed(1)} mm'),
          _e('Rango antero-post.', '${r.rangeAPMm.toStringAsFixed(1)} mm'),
          _e('Frecuencia 95%',     '${r.frequency95Hz.toStringAsFixed(2)} Hz'),
          _e('Simetria',           '${r.symmetryPercent.toStringAsFixed(1)} %'),
          if (r.rombergQuotient != null)
            _e('Cociente Romberg', r.rombergQuotient!.toStringAsFixed(3)),
        ]),
      ];

  // ── IMTP ──────────────────────────────────────────────────────────────────

  static List<pw.Widget> _imtpBody(
    ImtpResult r,
    List<double>? forceN,
    List<double>? timeS,
    double? bwN,
  ) => [
        _hero('FUERZA PICO ISOMETRICA', r.peakForceN.toStringAsFixed(0), 'N'),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            '${r.peakForceBW.toStringAsFixed(2)} x Peso corporal',
            style: pw.TextStyle(fontSize: 11, color: _cTextM),
          ),
        ),
        if (forceN != null && timeS != null) ...[
          pw.SizedBox(height: 10),
          _forceCurve(forceN, timeS, bwN),
        ],
        pw.SizedBox(height: 16),
        _section('FUERZA E IMPULSO'),
        _table([
          _e('Fuerza pico',          '${r.peakForceN.toStringAsFixed(0)} N'),
          _e('Fuerza relativa (BW)', '${r.peakForceBW.toStringAsFixed(2)} x PC'),
          _e('Impulso neto',         '${r.netImpulseNs.toStringAsFixed(1)} N*s'),
          _e('T. hasta fuerza pico', '${r.timeToPeakForceMs.toStringAsFixed(0)} ms'),
        ]),
        pw.SizedBox(height: 12),
        _section('TASA DE DESARROLLO DE FUERZA (RFD)'),
        _table([
          _e('RFD 50 ms',  '${(r.rfdAt50ms  / 1000).toStringAsFixed(1)} kN/s'),
          _e('RFD 100 ms', '${(r.rfdAt100ms / 1000).toStringAsFixed(1)} kN/s'),
          _e('RFD 200 ms', '${(r.rfdAt200ms / 1000).toStringAsFixed(1)} kN/s'),
        ]),
        pw.SizedBox(height: 12),
        _symSection(r.symmetry),
      ];

  // ── Multi-jump ────────────────────────────────────────────────────────────

  static List<pw.Widget> _multiBody(MultiJumpResult r) => [
        _hero('RSImod MEDIO', r.meanRsiMod.toStringAsFixed(3), ''),
        pw.SizedBox(height: 16),
        _section('RESUMEN (${r.jumpCount} SALTOS)'),
        _table([
          _e('Altura media',    '${r.meanHeightCm.toStringAsFixed(1)} cm'),
          _e('Contacto medio',  '${r.meanContactTimeMs.toStringAsFixed(0)} ms'),
          _e('RSImod medio',    r.meanRsiMod.toStringAsFixed(3)),
          _e('Indice de fatiga','${r.fatiguePercent.toStringAsFixed(1)} %'),
          _e('Variabilidad',    '${r.variabilityPercent.toStringAsFixed(1)} %'),
        ]),
        pw.SizedBox(height: 12),
        _section('DETALLE POR SALTO'),
        _jumpDetailTable(r.jumps),
      ];

  // ── Shared PDF widgets ────────────────────────────────────────────────────

  /// Hero metric card (dark navy background, large value).
  static pw.Widget _hero(String label, String value, String unit) {
    return pw.Container(
      padding:
          const pw.EdgeInsets.symmetric(vertical: 18, horizontal: 24),
      decoration: const pw.BoxDecoration(
        color: _cNavy,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              letterSpacing: 2,
              color: _cCyan,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 44,
                  fontWeight: pw.FontWeight.bold,
                  color: _cWhite,
                ),
              ),
              if (unit.isNotEmpty) ...[
                pw.SizedBox(width: 8),
                pw.Text(
                  unit,
                  style: pw.TextStyle(fontSize: 18, color: _cCyan),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Small uppercase section header label.
  static pw.Widget _section(String title) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: _cTextM,
            letterSpacing: 1.5,
          ),
        ),
      );

  /// Convenience helper — creates a MapEntry row for [_table].
  static MapEntry<String, String> _e(String label, String value) =>
      MapEntry(label, value);

  /// Two-column zebra-striped metrics table.
  static pw.Widget _table(List<MapEntry<String, String>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: _cBorder, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.2),
        1: pw.FlexColumnWidth(1.6),
      },
      children: rows.asMap().entries.map((entry) {
        final even = entry.key.isEven;
        final row  = entry.value;
        return pw.TableRow(
          decoration: pw.BoxDecoration(
            color: even ? _cSurface : _cWhite,
          ),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              child: pw.Text(
                row.key,
                style: pw.TextStyle(fontSize: 10, color: _cTextD),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              child: pw.Text(
                row.value,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _cNavy,
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  /// Detailed per-jump table with header row (multi-jump screen).
  static pw.Widget _jumpDetailTable(List<SingleJumpData> jumps) {
    const headers = ['#', 'Altura (cm)', 'Contacto (ms)', 'Vuelo (ms)', 'RSImod'];
    return pw.Table(
      border: pw.TableBorder.all(color: _cBorder, width: 0.5),
      children: [
        // ── Header ──────────────────────────────────────────────────────
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _cNavy),
          children: headers
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    child: pw.Text(
                      h,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _cCyan,
                      ),
                    ),
                  ))
              .toList(),
        ),
        // ── Data rows ───────────────────────────────────────────────────
        ...jumps.asMap().entries.map((entry) {
          final j    = entry.value;
          final even = entry.key.isEven;
          final vals = [
            j.jumpNumber.toString(),
            j.heightCm.toStringAsFixed(1),
            j.contactTimeMs.toStringAsFixed(0),
            j.flightTimeMs.toStringAsFixed(0),
            j.rsiMod.toStringAsFixed(3),
          ];
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: even ? _cSurface : _cWhite,
            ),
            children: vals
                .map((v) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: pw.Text(
                        v,
                        style: pw.TextStyle(fontSize: 9, color: _cTextD),
                      ),
                    ))
                .toList(),
          );
        }),
      ],
    );
  }

  /// Symmetry bar section with L/R percentages.
  static pw.Widget _symSection(SymmetryResult sym) {
    final isOk      = sym.isSymmetric;
    final leftColor  = isOk ? _cSuccess  : _cDanger;
    final rightColor = isOk ? _cSuccessL : _cDangerL;
    final leftFlex   = (sym.leftPercent  * 10).round().clamp(1, 990);
    final rightFlex  = (sym.rightPercent * 10).round().clamp(1, 990);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _section(sym.isTwoPlatform
            ? 'SIMETRIA'
            : 'SIMETRIA (estimada — 1 plataforma)'),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: const pw.BoxDecoration(
            color: _cSurface,
            border: pw.Border(
              top:    pw.BorderSide(color: _cBorder),
              bottom: pw.BorderSide(color: _cBorder),
              left:   pw.BorderSide(color: _cBorder),
              right:  pw.BorderSide(color: _cBorder),
            ),
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            children: [
              // ── Labels ─────────────────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'IZQ  ${sym.leftPercent.toStringAsFixed(1)} %',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: _cTextD,
                    ),
                  ),
                  pw.Text(
                    '${sym.rightPercent.toStringAsFixed(1)} %  DER',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: _cTextD,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              // ── Bar ────────────────────────────────────────────────
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: leftFlex,
                    child: pw.Container(
                      height: 12,
                      decoration: pw.BoxDecoration(color: leftColor),
                    ),
                  ),
                  pw.Expanded(
                    flex: rightFlex,
                    child: pw.Container(
                      height: 12,
                      decoration: pw.BoxDecoration(color: rightColor),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              // ── Status text ────────────────────────────────────────
              pw.Center(
                child: pw.Text(
                  isOk
                      ? 'Simetria correcta  (Δ ${sym.asymmetryIndexPct.toStringAsFixed(1)} %)'
                      : 'Asimetria elevada  (Δ ${sym.asymmetryIndexPct.toStringAsFixed(1)} %)',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: isOk ? _cSuccess : _cDanger,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Force-time curve ──────────────────────────────────────────────────────

  /// Renders a force-time curve using the pdf package's native [pw.Chart].
  ///
  /// Downsamples to ≤300 points; adds a thin BW reference line when provided.
  static pw.Widget _forceCurve(
      List<double> forceN, List<double> timeS, double? bwN) {
    const maxPts = 300;
    final fDs = _downsample(forceN, maxPts);
    final tDs = _downsample(timeS,  maxPts);

    final t0   = tDs.first;
    final tMax = (tDs.last - t0).clamp(0.001, double.infinity);

    // Force Y-range: rounded to nearest 100 N, ≥200 N span.
    double fMin = fDs.reduce(math.min);
    double fMax = fDs.reduce(math.max);
    fMin = (fMin / 100).floorToDouble() * 100.0;
    fMax = (fMax / 100).ceilToDouble()  * 100.0;
    if (fMax - fMin < 200) { fMin -= 100; fMax += 100; }

    // 5 evenly-spaced axis ticks (guaranteed sorted ascending, no duplicates).
    final xTicks = List.generate(5, (i) => tMax * i / 4.0);
    final yTicks = List.generate(5, (i) => fMin + (fMax - fMin) * i / 4.0);

    final bwInRange = bwN != null && bwN > fMin && bwN < fMax;

    final fData = <pw.PointChartValue>[
      for (int i = 0; i < fDs.length; i++)
        pw.PointChartValue(tDs[i] - t0, fDs[i]),
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _section('CURVA FUERZA-TIEMPO'),
        pw.SizedBox(height: 4),
        pw.SizedBox(
          height: 130,
          child: pw.Chart(
            grid: pw.CartesianGrid(
              xAxis: pw.FixedAxis<double>(
                xTicks,
                format: (v) => '${v.toStringAsFixed(1)}s',
                divisions: true,
                divisionsColor: _cBorder,
                color: _cTextM,
                width: 0.5,
                textStyle: pw.TextStyle(fontSize: 7, color: _cTextM),
              ),
              yAxis: pw.FixedAxis<double>(
                yTicks,
                format: (v) => '${(v / 1000).toStringAsFixed(1)}kN',
                divisions: true,
                divisionsColor: _cBorder,
                color: _cTextM,
                width: 0.5,
                textStyle: pw.TextStyle(fontSize: 7, color: _cTextM),
              ),
            ),
            datasets: [
              if (bwInRange)
                pw.LineDataSet(
                  data: [
                    pw.PointChartValue(0.0, bwN),
                    pw.PointChartValue(tMax, bwN),
                  ],
                  color: const PdfColor(0.65, 0.68, 0.72),
                  drawPoints: false,
                  lineWidth: 0.6,
                ),
              pw.LineDataSet(
                data: fData,
                color: _cCyan,
                drawPoints: false,
                lineWidth: 1.2,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static List<double> _downsample(List<double> data, int maxPts) {
    if (data.length <= maxPts) return data;
    final step = data.length / maxPts;
    return [
      for (int i = 0; i < maxPts; i++)
        data[(i * step).round().clamp(0, data.length - 1)],
    ];
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _fmtDate(DateTime dt) {
    final d  = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final h  = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$d/$mo/${dt.year}  $h:$mi';
  }

  static String _filename(TestResult r) {
    final d  = r.computedAt;
    // Include HHMMSS so same-day tests produce distinct filenames and don't
    // conflict when the previous PDF is still open in a viewer.
    final ts = '${d.year}${d.month.toString().padLeft(2, '0')}'
               '${d.day.toString().padLeft(2, '0')}_'
               '${d.hour.toString().padLeft(2, '0')}'
               '${d.minute.toString().padLeft(2, '0')}'
               '${d.second.toString().padLeft(2, '0')}';
    return 'InertiaX_${r.testType.name}_$ts.pdf';
  }
}

