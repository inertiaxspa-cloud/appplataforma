import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/l10n/app_strings.dart';
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
  static const _cWarning = PdfColor(0.961, 0.620, 0.043); // #F59E0B
  // Cover page dark background
  static const _cDark    = PdfColor(0.051, 0.059, 0.078); // #0D0F14
  // Lighter variants for the right half of symmetry bar
  static const _cSuccessL = PdfColor(0.133, 0.773, 0.367, 0.50);
  static const _cDangerL  = PdfColor(0.937, 0.267, 0.267, 0.45);

  // ── Month names in Spanish ─────────────────────────────────────────────────
  static const _meses = [
    '', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  // ── Public API ────────────────────────────────────────────────────────────

  /// Generates a PDF and opens the system share sheet.
  ///
  /// Pass [athlete] to include name and sport in the header.
  /// Pass [rawForceN] + [rawTimeS] to include a force-time curve above the
  /// metrics tables (typically from [TestStateNotifier.lastForceN/lastTimeS]).
  /// Pass [previousResult] to include a comparison column in the metrics table.
  /// Pass [compact] = true to produce a condensed single-page report (no cover,
  /// no normative table, smaller fonts).
  static Future<void> generateAndShare({
    required TestResult result,
    Athlete? athlete,
    List<double>? rawForceN,
    List<double>? rawTimeS,
    TestResult? previousResult,
    bool compact = false,
  }) async {
    // ── Load fonts that support extended Latin / UTF-8 characters ─────────
    // Default PDF fonts (Helvetica/Times) lack ñ, á, é, etc.
    final baseFont  = await PdfGoogleFonts.notoSansRegular();
    final boldFont  = await PdfGoogleFonts.notoSansBold();
    final italicFont = await PdfGoogleFonts.notoSansItalic();

    final doc = pw.Document(
      author: 'InertiaX',
      title: '${result.testType.displayName} — ${athlete?.name ?? AppStrings.get('pdf_athlete')}',
      theme: pw.ThemeData.withFont(
        base:   baseFont,
        bold:   boldFont,
        italic: italicFont,
      ),
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

    final athleteName = athlete?.name ?? AppStrings.get('pdf_athlete');

    // ── Cover page (only in full mode) ─────────────────────────────────────
    if (!compact) {
      _buildCoverPage(doc, result, athleteName);
    }

    // ── Executive summary page (only in full mode) ─────────────────────────
    if (!compact) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 44, vertical: 40),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(result, athlete),
              pw.SizedBox(height: 8),
              ..._buildExecutiveSummary(result),
              pw.Spacer(),
              _buildFooter(result),
            ],
          ),
        ),
      );
    }

    // ── Main content page(s) ──────────────────────────────────────────────
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 44, vertical: 40),
        header: (_) => _buildHeader(result, athlete),
        footer: (_) => _buildFooter(result),
        build:  (_) => _buildBody(result, fCurve, tCurve, bwRef,
            previousResult: previousResult, compact: compact),
      ),
    );

    // ── Normative table page (only in full mode) ───────────────────────────
    if (!compact) {
      final normWidgets = _buildNormativeTable(result);
      if (normWidgets != null) {
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.symmetric(horizontal: 44, vertical: 40),
            build: (ctx) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeader(result, athlete),
                pw.SizedBox(height: 8),
                ...normWidgets,
                pw.SizedBox(height: 20),
                ..._buildRecommendations(result),
                pw.Spacer(),
                _buildFooter(result),
              ],
            ),
          ),
        );
      }
    }

    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: _filename(result));
  }

  // ── Cover page ────────────────────────────────────────────────────────────

  /// Adds a full dark cover page to [doc].
  static void _buildCoverPage(
      pw.Document doc, TestResult result, String athleteName) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (ctx) {
          final testBadge = _shortTestName(result.testType);
          return pw.Stack(
            children: [
              // Dark background
              pw.Positioned.fill(
                child: pw.Container(color: _cDark),
              ),
              // Cyan accent bar at the top
              pw.Positioned(
                top: 0, left: 0, right: 0,
                child: pw.Container(
                  height: 8,
                  color: _cCyan,
                ),
              ),
              // Content
              pw.Positioned.fill(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 60, vertical: 80),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(height: 40),
                      // Brand name
                      pw.Text(
                        'InertiaX Force',
                        style: pw.TextStyle(
                          fontSize: 42,
                          fontWeight: pw.FontWeight.bold,
                          color: _cWhite,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        AppStrings.get('pdf_force_platforms'),
                        style: pw.TextStyle(
                          fontSize: 14,
                          color: _cCyan,
                          letterSpacing: 2,
                        ),
                      ),
                      pw.SizedBox(height: 50),
                      // Horizontal rule
                      pw.Container(
                        height: 1,
                        color: const PdfColor(1, 1, 1, 0.15),
                      ),
                      pw.SizedBox(height: 30),
                      // "Reporte de Rendimiento"
                      pw.Text(
                        AppStrings.get('pdf_title').toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 10,
                          letterSpacing: 3,
                          color: _cCyan,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 18),
                      // Athlete name
                      pw.Text(
                        athleteName,
                        style: pw.TextStyle(
                          fontSize: 28,
                          fontWeight: pw.FontWeight.bold,
                          color: _cWhite,
                        ),
                      ),
                      pw.SizedBox(height: 20),
                      // Test type badge
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: pw.BoxDecoration(
                          color: _cCyan,
                          borderRadius:
                              const pw.BorderRadius.all(pw.Radius.circular(6)),
                        ),
                        child: pw.Text(
                          testBadge,
                          style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                            color: _cDark,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 30),
                      // Date in Spanish
                      pw.Text(
                        _fmtDateSpanish(result.computedAt),
                        style: pw.TextStyle(
                          fontSize: 12,
                          color: const PdfColor(0.7, 0.75, 0.80),
                        ),
                      ),
                      pw.Spacer(),
                      // Bottom separator + footer note
                      pw.Container(
                        height: 1,
                        color: const PdfColor(1, 1, 1, 0.12),
                      ),
                      pw.SizedBox(height: 14),
                      pw.Text(
                        '${AppStrings.get('pdf_generated_by')}  •  '
                        '${AppStrings.get('pdf_platforms')}: ${result.platformCount}',
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: const PdfColor(0.5, 0.55, 0.60),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Executive Summary ─────────────────────────────────────────────────────

  /// Returns a list of widgets forming the Executive Summary section.
  static List<pw.Widget> _buildExecutiveSummary(TestResult result) {
    final cards = _executiveCards(result);
    if (cards.isEmpty) return [];

    // Build a 2×2 grid from up to 4 cards.
    final rows = <pw.Widget>[];
    for (int i = 0; i < cards.length; i += 2) {
      final pair = cards.sublist(i, math.min(i + 2, cards.length));
      rows.add(
        pw.Row(
          children: [
            for (int j = 0; j < pair.length; j++) ...[
              pw.Expanded(child: pair[j]),
              if (j < pair.length - 1) pw.SizedBox(width: 12),
            ],
            if (pair.length == 1) pw.Expanded(child: pw.SizedBox()),
          ],
        ),
      );
      if (i + 2 < cards.length) rows.add(pw.SizedBox(height: 12));
    }

    return [
      _section('RESUMEN EJECUTIVO'),
      pw.SizedBox(height: 10),
      ...rows,
    ];
  }

  /// Returns up to 4 metric cards for the executive summary.
  static List<pw.Widget> _executiveCards(TestResult result) {
    switch (result) {
      case DropJumpResult r:
        return [
          _execCard('Altura', r.jumpHeightCm.toStringAsFixed(1), 'cm'),
          _execCard('RSImod', r.rsiMod.toStringAsFixed(3), ''),
          _execCard('T. Contacto', r.contactTimeMs.toStringAsFixed(0), 'ms'),
          _execCard('Simetría', r.symmetry.asymmetryIndexPct > 0
              ? (100 - r.symmetry.asymmetryIndexPct).toStringAsFixed(1)
              : '100.0', '%'),
        ];
      case JumpResult r:
        return [
          _execCard('Altura', r.jumpHeightCm.toStringAsFixed(1), 'cm'),
          _execCard('F. Pico', r.peakForceN.toStringAsFixed(0), 'N'),
          _execCard('Pot. Pico', r.peakPowerSayersW.toStringAsFixed(0), 'W'),
          _execCard('Simetría', r.symmetry.asymmetryIndexPct > 0
              ? (100 - r.symmetry.asymmetryIndexPct).toStringAsFixed(1)
              : '100.0', '%'),
        ];
      case ImtpResult r:
        return [
          _execCard('F. Pico', r.peakForceN.toStringAsFixed(0), 'N'),
          _execCard('F. Relativa', r.peakForceBW.toStringAsFixed(2), '× PC'),
          _execCard('RFD 200ms', (r.rfdAt200ms / 1000).toStringAsFixed(1), 'kN/s'),
          _execCard('Simetría', r.symmetry.asymmetryIndexPct > 0
              ? (100 - r.symmetry.asymmetryIndexPct).toStringAsFixed(1)
              : '100.0', '%'),
        ];
      case CoPResult r:
        return [
          _execCard('Trayectoria', r.pathLengthMm.toStringAsFixed(0), 'mm'),
          _execCard('Área Elipse', r.areaEllipseMm2.toStringAsFixed(0), 'mm²'),
          _execCard('Vel. Media', r.meanVelocityMmS.toStringAsFixed(1), 'mm/s'),
          _execCard('Simetría', r.symmetryPercent.toStringAsFixed(1), '%'),
        ];
      case MultiJumpResult r:
        return [
          _execCard('Alt. Media', r.meanHeightCm.toStringAsFixed(1), 'cm'),
          _execCard('RSImod', r.meanRsiMod.toStringAsFixed(3), ''),
          _execCard('Fatiga', r.fatiguePercent.toStringAsFixed(1), '%'),
          _execCard('Variabilidad', r.variabilityPercent.toStringAsFixed(1), '%'),
        ];
      case FreeTestResult r:
        return [
          _execCard('F. Pico', r.peakForceN.toStringAsFixed(0), 'N'),
          _execCard('F. Media', r.meanForceN.toStringAsFixed(0), 'N'),
          _execCard('Duración', r.durationS.toStringAsFixed(1), 's'),
          _execCard('Impulso', r.totalImpulseNs.toStringAsFixed(0), 'N·s'),
        ];
    }
  }

  /// Single executive summary card.
  static pw.Widget _execCard(String label, String value, String unit) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: const pw.BoxDecoration(
        color: _cNavy,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 7,
              letterSpacing: 1.5,
              color: _cCyan,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 32,
                  fontWeight: pw.FontWeight.bold,
                  color: _cWhite,
                ),
              ),
              if (unit.isNotEmpty) ...[
                pw.SizedBox(width: 5),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                    unit,
                    style: pw.TextStyle(fontSize: 12, color: _cCyan),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Normative Table ───────────────────────────────────────────────────────

  /// Returns normative table widgets for the given result type, or null if
  /// there is no normative data for this test type.
  static List<pw.Widget>? _buildNormativeTable(TestResult result) {
    if (result is DropJumpResult) {
      return _normTableDJ(result);
    } else if (result is JumpResult) {
      return _normTableJump(result);
    } else if (result is ImtpResult) {
      return _normTableImtp(result);
    } else if (result is CoPResult) {
      return _normTableCoP(result);
    }
    return null;
  }

  static List<pw.Widget> _normTableJump(JumpResult r) {
    final val = r.jumpHeightCm;
    // Levels: label, min (inclusive), max (exclusive), color
    final levels = [
      _NormLevel('Elite',       45.0, double.infinity, _cSuccess),
      _NormLevel('Avanzado',    35.0, 45.0,             _cCyan),
      _NormLevel('Intermedio',  25.0, 35.0,             _cWarning),
      _NormLevel('Básico',      0.0,  25.0,             _cDanger),
    ];
    return _normSection(
      title: 'TABLA NORMATIVA — ALTURA DE SALTO (CMJ/SJ)',
      headers: ['Nivel', 'Rango', ''],
      levels: levels,
      getValue: (l) => l.min == 0
          ? '< 25 cm'
          : l.max == double.infinity
              ? '> ${l.min.toStringAsFixed(0)} cm'
              : '${l.min.toStringAsFixed(0)} – ${l.max.toStringAsFixed(0)} cm',
      isCurrent: (l) => val >= l.min && val < l.max,
    );
  }

  static List<pw.Widget> _normTableDJ(DropJumpResult r) {
    final val = r.rsiMod;
    final levels = [
      _NormLevel('Elite',       1.2, double.infinity, _cSuccess),
      _NormLevel('Avanzado',    0.9, 1.2,             _cCyan),
      _NormLevel('Intermedio',  0.6, 0.9,             _cWarning),
      _NormLevel('Básico',      0.0, 0.6,             _cDanger),
    ];
    return _normSection(
      title: 'TABLA NORMATIVA — RSImod (DROP JUMP)',
      headers: ['Nivel', 'Rango RSImod', ''],
      levels: levels,
      getValue: (l) => l.min == 0
          ? '< 0.60'
          : l.max == double.infinity
              ? '> ${l.min.toStringAsFixed(2)}'
              : '${l.min.toStringAsFixed(2)} – ${l.max.toStringAsFixed(2)}',
      isCurrent: (l) => val >= l.min && val < l.max,
    );
  }

  static List<pw.Widget> _normTableImtp(ImtpResult r) {
    final val = r.peakForceBW;
    final levels = [
      _NormLevel('Elite',       2.5, double.infinity, _cSuccess),
      _NormLevel('Avanzado',    2.0, 2.5,             _cCyan),
      _NormLevel('Intermedio',  1.5, 2.0,             _cWarning),
      _NormLevel('Básico',      0.0, 1.5,             _cDanger),
    ];
    return _normSection(
      title: 'TABLA NORMATIVA — FUERZA RELATIVA IMTP (× PC)',
      headers: ['Nivel', 'Rango (× BW)', ''],
      levels: levels,
      getValue: (l) => l.min == 0
          ? '< 1.5 × BW'
          : l.max == double.infinity
              ? '> ${l.min.toStringAsFixed(1)} × BW'
              : '${l.min.toStringAsFixed(1)} – ${l.max.toStringAsFixed(1)} × BW',
      isCurrent: (l) => val >= l.min && val < l.max,
    );
  }

  static List<pw.Widget> _normTableCoP(CoPResult r) {
    final val = r.pathLengthMm;
    // For CoP lower is better — elite has smallest path.
    final levels = [
      _NormLevel('Elite',       0.0,   400.0,          _cSuccess),
      _NormLevel('Avanzado',    400.0, 600.0,           _cCyan),
      _NormLevel('Intermedio',  600.0, 900.0,           _cWarning),
      _NormLevel('Básico',      900.0, double.infinity, _cDanger),
    ];
    return _normSection(
      title: 'TABLA NORMATIVA — TRAYECTORIA CoP (mm)',
      headers: ['Nivel', 'Rango (mm)', ''],
      levels: levels,
      getValue: (l) => l.min == 0
          ? '< 400 mm'
          : l.max == double.infinity
              ? '> ${l.min.toStringAsFixed(0)} mm'
              : '${l.min.toStringAsFixed(0)} – ${l.max.toStringAsFixed(0)} mm',
      isCurrent: (l) => val >= l.min && val < l.max,
    );
  }

  static List<pw.Widget> _normSection({
    required String title,
    required List<String> headers,
    required List<_NormLevel> levels,
    required String Function(_NormLevel) getValue,
    required bool Function(_NormLevel) isCurrent,
  }) {
    return [
      _section(title),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder.all(color: _cBorder, width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.6),
          1: pw.FlexColumnWidth(2.2),
          2: pw.FixedColumnWidth(30),
        },
        children: [
          // Header row
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _cNavy),
            children: headers
                .map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
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
          // Data rows
          ...levels.map((lvl) {
            final current = isCurrent(lvl);
            return pw.TableRow(
              decoration: pw.BoxDecoration(
                color: current
                    ? PdfColor(lvl.color.red, lvl.color.green, lvl.color.blue, 0.12)
                    : _cWhite,
              ),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  child: pw.Text(
                    lvl.label,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: current
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                      color: current ? lvl.color : _cTextD,
                    ),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  child: pw.Text(
                    getValue(lvl),
                    style: pw.TextStyle(fontSize: 10, color: _cTextD),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6, vertical: 6),
                  child: pw.Text(
                    current ? '\u25CF' : '',
                    style: pw.TextStyle(
                      fontSize: 14,
                      color: lvl.color,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    ];
  }

  // ── Recommendations ───────────────────────────────────────────────────────

  /// Returns recommendation widgets based on the result values.
  static List<pw.Widget> _buildRecommendations(TestResult result) {
    final recs = <_Recommendation>[];

    // ── Symmetry check (applies to all results with symmetry) ───────────────
    SymmetryResult? sym;
    if (result is JumpResult) sym = result.symmetry;
    if (result is ImtpResult) sym = result.symmetry;

    if (sym != null && (100 - sym.asymmetryIndexPct) < 85) {
      recs.add(_Recommendation(
        icon: '\u26A0',
        color: _cWarning,
        text: 'Asimetría significativa detectada. Evalúa déficit muscular '
            'en lado dominante.',
      ));
    }

    // ── CoP symmetry ─────────────────────────────────────────────────────────
    if (result is CoPResult && result.symmetryPercent < 85) {
      recs.add(_Recommendation(
        icon: '\u26A0',
        color: _cWarning,
        text: 'Asimetría significativa detectada. Evalúa déficit muscular '
            'en lado dominante.',
      ));
    }

    // ── Jump height ───────────────────────────────────────────────────────────
    if (result is JumpResult && result is! DropJumpResult &&
        result.jumpHeightCm < 25) {
      recs.add(_Recommendation(
        icon: '\u{1F4A1}',
        color: _cCyan,
        text: 'Nivel básico. Enfoca en fuerza máxima y técnica de salto.',
      ));
    }

    // ── RSImod (Drop Jump) ────────────────────────────────────────────────────
    if (result is DropJumpResult && result.rsiMod < 0.8) {
      recs.add(_Recommendation(
        icon: '\u{1F4A1}',
        color: _cCyan,
        text: 'RSI bajo. Trabaja ejercicios de potencia reactiva '
            '(Drop Jumps desde 20 cm).',
      ));
    }

    // ── IMTP peak force ───────────────────────────────────────────────────────
    if (result is ImtpResult && result.peakForceBW > 2.5) {
      recs.add(_Recommendation(
        icon: '\u2705',
        color: _cSuccess,
        text: 'Excelente fuerza máxima. Mantén el trabajo de RFD.',
      ));
    }

    // ── CoP path length ───────────────────────────────────────────────────────
    if (result is CoPResult && result.pathLengthMm > 800) {
      recs.add(_Recommendation(
        icon: '\u26A0',
        color: _cWarning,
        text: 'Equilibrio por debajo del promedio. Incluye ejercicios '
            'propioceptivos.',
      ));
    }

    if (recs.isEmpty) return [];

    return [
      _section('RECOMENDACIONES'),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: _cSurface,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          border: pw.Border.all(color: _cBorder, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: recs.map((rec) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    rec.icon,
                    style: pw.TextStyle(fontSize: 14, color: rec.color),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Text(
                      rec.text,
                      style: pw.TextStyle(fontSize: 10, color: _cTextD),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    ];
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
              'InertiaX  |  ${AppStrings.get('pdf_platforms')}: ${r.platformCount}',
              style: pw.TextStyle(fontSize: 8, color: _cTextM),
            ),
            pw.Text(
              AppStrings.get('pdf_generated_by'),
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
    double? bwN, {
    TestResult? previousResult,
    bool compact = false,
  }) =>
      switch (r) {
        DropJumpResult res  => _djBody(res,   forceN, timeS, bwN,
            prev: previousResult is DropJumpResult ? previousResult : null,
            compact: compact),
        JumpResult res      => _jumpBody(res, forceN, timeS, bwN,
            prev: previousResult is JumpResult ? previousResult : null,
            compact: compact),
        CoPResult res       => _copBody(res,
            prev: previousResult is CoPResult ? previousResult : null,
            compact: compact),
        ImtpResult res      => _imtpBody(res, forceN, timeS, bwN,
            prev: previousResult is ImtpResult ? previousResult : null,
            compact: compact),
        MultiJumpResult res => _multiBody(res, compact: compact),
        FreeTestResult _    => [],
      };

  // ── Jump (CMJ / SJ) ───────────────────────────────────────────────────────

  static List<pw.Widget> _jumpBody(
    JumpResult r,
    List<double>? forceN,
    List<double>? timeS,
    double? bwN, {
    JumpResult? prev,
    bool compact = false,
  }) {
    final double? fSize = compact ? 8.0 : null;
    return [
      if (!compact) _hero('ALTURA DE SALTO', r.jumpHeightCm.toStringAsFixed(1), 'cm'),
      if (forceN != null && timeS != null && !compact) ...[
        pw.SizedBox(height: 10),
        _forceCurve(forceN, timeS, bwN),
        // Velocity-time curve (integration of force)
        ..._velocityCurve(forceN, timeS, r.bodyWeightN),
      ],
      pw.SizedBox(height: compact ? 8 : 16),
      _section('RENDIMIENTO'),
      _tableWithPrev(
        rows: [
          _e('Altura de salto',         '${r.jumpHeightCm.toStringAsFixed(1)} cm'),
          _e('Tiempo de vuelo',         '${r.flightTimeMs.toStringAsFixed(0)} ms'),
          _e('Fuerza pico',             '${r.peakForceN.toStringAsFixed(0)} N'),
          _e('Fuerza media',            '${r.meanForceN.toStringAsFixed(0)} N'),
          _e('Potencia pico (Sayers)',  '${r.peakPowerSayersW.toStringAsFixed(0)} W'),
          _e('Potencia pico (impulso)', '${r.peakPowerImpulseW.toStringAsFixed(0)} W'),
        ],
        prevRows: prev == null ? null : [
          _e('Altura de salto',         '${prev.jumpHeightCm.toStringAsFixed(1)} cm'),
          _e('Tiempo de vuelo',         '${prev.flightTimeMs.toStringAsFixed(0)} ms'),
          _e('Fuerza pico',             '${prev.peakForceN.toStringAsFixed(0)} N'),
          _e('Fuerza media',            '${prev.meanForceN.toStringAsFixed(0)} N'),
          _e('Potencia pico (Sayers)',  '${prev.peakPowerSayersW.toStringAsFixed(0)} W'),
          _e('Potencia pico (impulso)', '${prev.peakPowerImpulseW.toStringAsFixed(0)} W'),
        ],
        deltas: prev == null ? null : [
          r.jumpHeightCm       - prev.jumpHeightCm,
          r.flightTimeMs       - prev.flightTimeMs,
          r.peakForceN         - prev.peakForceN,
          r.meanForceN         - prev.meanForceN,
          r.peakPowerSayersW   - prev.peakPowerSayersW,
          r.peakPowerImpulseW  - prev.peakPowerImpulseW,
        ],
        fontSize: fSize,
      ),
      pw.SizedBox(height: compact ? 8 : 12),
      _section('TASA DE DESARROLLO DE FUERZA (RFD)'),
      _tableWithPrev(
        rows: [
          _e('RFD 50 ms',             '${(r.rfdAt50ms  / 1000).toStringAsFixed(1)} kN/s'),
          _e('RFD 100 ms',            '${(r.rfdAt100ms / 1000).toStringAsFixed(1)} kN/s'),
          _e('RFD 200 ms',            '${(r.rfdAt200ms / 1000).toStringAsFixed(1)} kN/s'),
          _e('T. hasta fuerza pico',  '${r.timeToPeakForceMs.toStringAsFixed(0)} ms'),
        ],
        prevRows: prev == null ? null : [
          _e('RFD 50 ms',             '${(prev.rfdAt50ms  / 1000).toStringAsFixed(1)} kN/s'),
          _e('RFD 100 ms',            '${(prev.rfdAt100ms / 1000).toStringAsFixed(1)} kN/s'),
          _e('RFD 200 ms',            '${(prev.rfdAt200ms / 1000).toStringAsFixed(1)} kN/s'),
          _e('T. hasta fuerza pico',  '${prev.timeToPeakForceMs.toStringAsFixed(0)} ms'),
        ],
        deltas: prev == null ? null : [
          r.rfdAt50ms  - prev.rfdAt50ms,
          r.rfdAt100ms - prev.rfdAt100ms,
          r.rfdAt200ms - prev.rfdAt200ms,
          r.timeToPeakForceMs - prev.timeToPeakForceMs,
        ],
        fontSize: fSize,
      ),
      if (!compact) ...[
        pw.SizedBox(height: 12),
        _section('IMPULSO Y FASES'),
        _table([
          _e('Impulso propulsivo', '${r.propulsiveImpulseNs.toStringAsFixed(1)} N*s'),
          _e('Impulso de frenado', '${r.brakingImpulseNs.toStringAsFixed(1)} N*s'),
          _e('Fase excéntrica',    '${r.eccentricDurationMs.toStringAsFixed(0)} ms'),
          _e('Fase concéntrica',   '${r.concentricDurationMs.toStringAsFixed(0)} ms'),
          _e('Fuerza de despegue', '${r.takeoffForceN.toStringAsFixed(0)} N'),
          _e(AppStrings.get('pdf_body_weight'), '${(r.bodyWeightN / 9.81).toStringAsFixed(1)} kg'),
        ]),
      ],
      pw.SizedBox(height: compact ? 8 : 12),
      _symSection(r.symmetry),
    ];
  }

  // ── Drop Jump ─────────────────────────────────────────────────────────────

  static List<pw.Widget> _djBody(
    DropJumpResult r,
    List<double>? forceN,
    List<double>? timeS,
    double? bwN, {
    DropJumpResult? prev,
    bool compact = false,
  }) =>
      [
        ..._jumpBody(r, forceN, timeS, bwN,
            prev: prev, compact: compact),
        pw.SizedBox(height: compact ? 8 : 12),
        _section('DROP JUMP'),
        _tableWithPrev(
          rows: [
            _e('Tiempo de contacto', '${r.contactTimeMs.toStringAsFixed(0)} ms'),
            _e('RSImod',              r.rsiMod.toStringAsFixed(3)),
          ],
          prevRows: prev == null ? null : [
            _e('Tiempo de contacto', '${prev.contactTimeMs.toStringAsFixed(0)} ms'),
            _e('RSImod',              prev.rsiMod.toStringAsFixed(3)),
          ],
          deltas: prev == null ? null : [
            r.contactTimeMs - prev.contactTimeMs,
            r.rsiMod        - prev.rsiMod,
          ],
          fontSize: compact ? 8.0 : null,
        ),
      ];

  // ── CoP / Balance ─────────────────────────────────────────────────────────

  static List<pw.Widget> _copBody(CoPResult r, {
    CoPResult? prev,
    bool compact = false,
  }) =>
      [
        if (!compact)
          _hero('ÁREA ELIPSE 95%', r.areaEllipseMm2.toStringAsFixed(0), 'mm²'),
        pw.SizedBox(height: compact ? 8 : 16),
        _section('CONDICIONES'),
        _table([
          _e('Condición',
              r.condition == 'OA' ? 'Ojos abiertos' : 'Ojos cerrados'),
          _e('Postura', r.stance == 'bipedal'
              ? 'Bipodal'
              : r.stance == 'left'
                  ? 'Unipodal izquierdo'
                  : 'Unipodal derecho'),
          _e('Duración', '${r.testDurationS.toStringAsFixed(1)} s'),
        ]),
        pw.SizedBox(height: compact ? 8 : 12),
        _section('ESTABILIDAD'),
        _tableWithPrev(
          rows: [
            _e('Área elipse 95%',    '${r.areaEllipseMm2.toStringAsFixed(0)} mm²'),
            _e('Long. trayectoria',  '${r.pathLengthMm.toStringAsFixed(0)} mm'),
            _e('Velocidad media',    '${r.meanVelocityMmS.toStringAsFixed(1)} mm/s'),
            _e('Rango medio-lat.',   '${r.rangeMLMm.toStringAsFixed(1)} mm'),
            _e('Rango antero-post.', '${r.rangeAPMm.toStringAsFixed(1)} mm'),
            _e('Frecuencia 95%',     '${r.frequency95Hz.toStringAsFixed(2)} Hz'),
            _e('Simetría',           '${r.symmetryPercent.toStringAsFixed(1)} %'),
            if (r.rombergQuotient != null)
              _e('Cociente Romberg', r.rombergQuotient!.toStringAsFixed(3)),
          ],
          prevRows: prev == null ? null : [
            _e('Area elipse 95%',    '${prev.areaEllipseMm2.toStringAsFixed(0)} mm2'),
            _e('Long. trayectoria',  '${prev.pathLengthMm.toStringAsFixed(0)} mm'),
            _e('Velocidad media',    '${prev.meanVelocityMmS.toStringAsFixed(1)} mm/s'),
            _e('Rango medio-lat.',   '${prev.rangeMLMm.toStringAsFixed(1)} mm'),
            _e('Rango antero-post.', '${prev.rangeAPMm.toStringAsFixed(1)} mm'),
            _e('Frecuencia 95%',     '${prev.frequency95Hz.toStringAsFixed(2)} Hz'),
            _e('Simetria',           '${prev.symmetryPercent.toStringAsFixed(1)} %'),
            if (prev.rombergQuotient != null)
              _e('Cociente Romberg', prev.rombergQuotient!.toStringAsFixed(3)),
          ],
          deltas: prev == null ? null : [
            r.areaEllipseMm2   - prev.areaEllipseMm2,
            r.pathLengthMm     - prev.pathLengthMm,
            r.meanVelocityMmS  - prev.meanVelocityMmS,
            r.rangeMLMm        - prev.rangeMLMm,
            r.rangeAPMm        - prev.rangeAPMm,
            r.frequency95Hz    - prev.frequency95Hz,
            r.symmetryPercent  - prev.symmetryPercent,
            if (r.rombergQuotient != null && prev.rombergQuotient != null)
              r.rombergQuotient! - prev.rombergQuotient!,
          ],
          fontSize: compact ? 8.0 : null,
        ),
      ];

  // ── IMTP ──────────────────────────────────────────────────────────────────

  static List<pw.Widget> _imtpBody(
    ImtpResult r,
    List<double>? forceN,
    List<double>? timeS,
    double? bwN, {
    ImtpResult? prev,
    bool compact = false,
  }) =>
      [
        if (!compact) ...[
          _hero('FUERZA PICO ISOMÉTRICA', r.peakForceN.toStringAsFixed(0), 'N'),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              '${r.peakForceBW.toStringAsFixed(2)} x ${AppStrings.get('pdf_body_weight')}',
              style: pw.TextStyle(fontSize: 11, color: _cTextM),
            ),
          ),
        ],
        if (forceN != null && timeS != null && !compact) ...[
          pw.SizedBox(height: 10),
          _forceCurve(forceN, timeS, bwN),
        ],
        pw.SizedBox(height: compact ? 8 : 16),
        _section('FUERZA E IMPULSO'),
        _tableWithPrev(
          rows: [
            _e('Fuerza pico',          '${r.peakForceN.toStringAsFixed(0)} N'),
            _e('Fuerza relativa (BW)', '${r.peakForceBW.toStringAsFixed(2)} x PC'),
            _e('Impulso neto',         '${r.netImpulseNs.toStringAsFixed(1)} N*s'),
            _e('T. hasta fuerza pico', '${r.timeToPeakForceMs.toStringAsFixed(0)} ms'),
          ],
          prevRows: prev == null ? null : [
            _e('Fuerza pico',          '${prev.peakForceN.toStringAsFixed(0)} N'),
            _e('Fuerza relativa (BW)', '${prev.peakForceBW.toStringAsFixed(2)} x PC'),
            _e('Impulso neto',         '${prev.netImpulseNs.toStringAsFixed(1)} N*s'),
            _e('T. hasta fuerza pico', '${prev.timeToPeakForceMs.toStringAsFixed(0)} ms'),
          ],
          deltas: prev == null ? null : [
            r.peakForceN        - prev.peakForceN,
            r.peakForceBW       - prev.peakForceBW,
            r.netImpulseNs      - prev.netImpulseNs,
            r.timeToPeakForceMs - prev.timeToPeakForceMs,
          ],
          fontSize: compact ? 8.0 : null,
        ),
        pw.SizedBox(height: compact ? 8 : 12),
        _section('TASA DE DESARROLLO DE FUERZA (RFD)'),
        _tableWithPrev(
          rows: [
            _e('RFD 50 ms',  '${(r.rfdAt50ms  / 1000).toStringAsFixed(1)} kN/s'),
            _e('RFD 100 ms', '${(r.rfdAt100ms / 1000).toStringAsFixed(1)} kN/s'),
            _e('RFD 200 ms', '${(r.rfdAt200ms / 1000).toStringAsFixed(1)} kN/s'),
          ],
          prevRows: prev == null ? null : [
            _e('RFD 50 ms',  '${(prev.rfdAt50ms  / 1000).toStringAsFixed(1)} kN/s'),
            _e('RFD 100 ms', '${(prev.rfdAt100ms / 1000).toStringAsFixed(1)} kN/s'),
            _e('RFD 200 ms', '${(prev.rfdAt200ms / 1000).toStringAsFixed(1)} kN/s'),
          ],
          deltas: prev == null ? null : [
            r.rfdAt50ms  - prev.rfdAt50ms,
            r.rfdAt100ms - prev.rfdAt100ms,
            r.rfdAt200ms - prev.rfdAt200ms,
          ],
          fontSize: compact ? 8.0 : null,
        ),
        pw.SizedBox(height: compact ? 8 : 12),
        _symSection(r.symmetry),
      ];

  // ── Multi-jump ────────────────────────────────────────────────────────────

  static List<pw.Widget> _multiBody(MultiJumpResult r,
      {bool compact = false}) =>
      [
        if (!compact)
          _hero('RSImod MEDIO', r.meanRsiMod.toStringAsFixed(3), ''),
        pw.SizedBox(height: compact ? 8 : 16),
        _section('RESUMEN (${r.jumpCount} SALTOS)'),
        _table([
          _e('Altura media',    '${r.meanHeightCm.toStringAsFixed(1)} cm'),
          _e('Contacto medio',  '${r.meanContactTimeMs.toStringAsFixed(0)} ms'),
          _e('RSImod medio',    r.meanRsiMod.toStringAsFixed(3)),
          _e('Indice de fatiga','${r.fatiguePercent.toStringAsFixed(1)} %'),
          _e('Variabilidad',    '${r.variabilityPercent.toStringAsFixed(1)} %'),
        ]),
        pw.SizedBox(height: compact ? 8 : 12),
        _section('DETALLE POR SALTO'),
        _jumpDetailTable(r.jumps, compact: compact),
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

  /// Two-column zebra-striped metrics table (no comparison columns).
  static pw.Widget _table(List<MapEntry<String, String>> rows,
      {double? fontSize}) {
    return _tableWithPrev(rows: rows, fontSize: fontSize);
  }

  /// Two-column table, optionally extended with "Anterior" and "Δ" columns
  /// when [prevRows] and [deltas] are provided.
  static pw.Widget _tableWithPrev({
    required List<MapEntry<String, String>> rows,
    List<MapEntry<String, String>>? prevRows,
    List<double>? deltas,
    double? fontSize,
  }) {
    final hasPrev = prevRows != null &&
        deltas != null &&
        prevRows.length == rows.length &&
        deltas.length == rows.length;
    final fs = fontSize ?? 10.0;

    return pw.Table(
      border: pw.TableBorder.all(color: _cBorder, width: 0.5),
      columnWidths: hasPrev
          ? {
              0: const pw.FlexColumnWidth(2.2),
              1: const pw.FlexColumnWidth(1.4),
              2: const pw.FlexColumnWidth(1.4),
              3: const pw.FlexColumnWidth(1.0),
            }
          : const {
              0: pw.FlexColumnWidth(2.2),
              1: pw.FlexColumnWidth(1.6),
            },
      children: [
        // Optional header row when previous data is present
        if (hasPrev)
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _cNavy),
            children: ['Métrica', 'Actual', 'Anterior', '\u0394']
                .map((h) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: pw.Text(
                        h,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: _cCyan,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ...rows.asMap().entries.map((entry) {
          final even   = entry.key.isEven;
          final row    = entry.value;
          final delta  = hasPrev ? deltas[entry.key] : null;
          final prevV  = hasPrev ? prevRows[entry.key].value : null;
          final deltaStr = delta == null
              ? ''
              : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(delta.abs() < 10 ? 2 : 0)}';
          final deltaColor = delta == null
              ? _cTextM
              : (delta >= 0 ? _cSuccess : _cDanger);

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
                  style: pw.TextStyle(fontSize: fs, color: _cTextD),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                child: pw.Text(
                  row.value,
                  style: pw.TextStyle(
                    fontSize: fs,
                    fontWeight: pw.FontWeight.bold,
                    color: _cNavy,
                  ),
                ),
              ),
              if (hasPrev) ...[
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  child: pw.Text(
                    prevV ?? '',
                    style: pw.TextStyle(fontSize: fs, color: _cTextM),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6, vertical: 5),
                  child: pw.Text(
                    deltaStr,
                    style: pw.TextStyle(
                      fontSize: fs - 1,
                      fontWeight: pw.FontWeight.bold,
                      color: deltaColor,
                    ),
                  ),
                ),
              ],
            ],
          );
        }),
      ],
    );
  }

  /// Detailed per-jump table with header row (multi-jump screen).
  static pw.Widget _jumpDetailTable(List<SingleJumpData> jumps,
      {bool compact = false}) {
    const headers = ['#', 'Altura (cm)', 'Contacto (ms)', 'Vuelo (ms)', 'RSImod'];
    final fs = compact ? 8.0 : 9.0;
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
                        fontSize: fs,
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
                        style: pw.TextStyle(fontSize: fs, color: _cTextD),
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
            ? 'SIMETRÍA'
            : 'SIMETRÍA (estimada — 1 plataforma)'),
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
                      ? 'Simetría correcta  (Δ ${sym.asymmetryIndexPct.toStringAsFixed(1)} %)'
                      : 'Asimetría elevada  (Δ ${sym.asymmetryIndexPct.toStringAsFixed(1)} %)',
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
    if (forceN.isEmpty || timeS.isEmpty) return pw.SizedBox();
    final fDs = _downsample(forceN, maxPts);
    final tDs = _downsample(timeS,  maxPts);
    if (fDs.isEmpty || tDs.isEmpty) return pw.SizedBox();

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
        _section(AppStrings.get('pdf_force_time_curve').toUpperCase()),
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

  // ── Velocity-time curve (integration) ────────────────────────────────────

  /// Computes velocity by numerical integration (trapezoid rule) of
  /// (F - BW) / mass and renders it as a chart.
  ///
  /// Returns an empty list when:
  /// - [forceN] or [timeS] are empty / too short.
  /// - [bodyWeightN] is zero or negative.
  static List<pw.Widget> _velocityCurve(
    List<double> forceN,
    List<double> timeS,
    double bodyWeightN,
  ) {
    if (forceN.length < 10 ||
        timeS.length != forceN.length ||
        bodyWeightN <= 0) {
      return [];
    }

    const maxPts  = 300;
    final fDs     = _downsample(forceN, maxPts);
    final tDs     = _downsample(timeS,  maxPts);
    final massKg  = bodyWeightN / 9.81;

    // ── Find movement onset: first index where force deviates > 5% BW ─────
    // This prevents drift accumulation during the quiet-standing (settling) period.
    // We use the mean of the first 200ms as the true body-weight reference.
    final bwRef = _estimateBodyWeight(fDs, tDs);
    final deviationThreshold = bwRef * 0.05; // 5% of body weight
    int onsetIdx = 0;
    for (int i = 1; i < fDs.length; i++) {
      if ((fDs[i] - bwRef).abs() > deviationThreshold) {
        onsetIdx = math.max(0, i - 5); // include 5 samples before onset
        break;
      }
    }
    final t0 = tDs[onsetIdx];

    // Trapezoid integration starting from onsetIdx (v=0 at onset).
    final velMs = List<double>.filled(fDs.length, 0.0);
    for (int i = onsetIdx + 1; i < fDs.length; i++) {
      final dt    = tDs[i] - tDs[i - 1];
      final fNet0 = fDs[i - 1] - bodyWeightN;
      final fNet1 = fDs[i]     - bodyWeightN;
      velMs[i]    = velMs[i - 1] + (fNet0 + fNet1) / 2.0 / massKg * dt;
    }

    // Only plot from onsetIdx onwards (no pre-movement flat line).
    final velPlot = velMs.sublist(onsetIdx);
    final tPlot   = tDs.sublist(onsetIdx);

    // Y range: round to nearest 0.5 m/s, ≥1 m/s span.
    double vMin = velPlot.reduce(math.min);
    double vMax = velPlot.reduce(math.max);
    vMin = (vMin / 0.5).floorToDouble() * 0.5;
    vMax = (vMax / 0.5).ceilToDouble()  * 0.5;
    if (vMax - vMin < 1.0) { vMin -= 0.5; vMax += 0.5; }

    final tMax     = (tPlot.last - t0).clamp(0.001, double.infinity);
    final xTicks   = List.generate(5, (i) => tMax * i / 4.0);
    final yTicks   = List.generate(5, (i) => vMin + (vMax - vMin) * i / 4.0);

    final vData = <pw.PointChartValue>[
      for (int i = 0; i < tPlot.length; i++)
        pw.PointChartValue(tPlot[i] - t0, velPlot[i]),
    ];

    return [
      pw.SizedBox(height: 8),
      _section('CURVA VELOCIDAD-TIEMPO (integración)'),
      pw.SizedBox(height: 4),
      pw.SizedBox(
        height: 110,
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
              format: (v) => '${v.toStringAsFixed(1)}m/s',
              divisions: true,
              divisionsColor: _cBorder,
              color: _cTextM,
              width: 0.5,
              textStyle: pw.TextStyle(fontSize: 7, color: _cTextM),
            ),
          ),
          datasets: [
            pw.LineDataSet(
              data: vData,
              color: _cSuccess,
              drawPoints: false,
              lineWidth: 1.2,
            ),
          ],
        ),
      ),
    ];
  }

  /// Estimates body weight as the mean of the first 200ms of the signal.
  /// Robust against drift because it uses the quiet-standing baseline.
  static double _estimateBodyWeight(List<double> fDs, List<double> tDs) {
    final t200 = tDs.first + 0.20;
    double sum = 0; int count = 0;
    for (int i = 0; i < fDs.length && tDs[i] <= t200; i++) {
      sum += fDs[i]; count++;
    }
    return count > 0 ? sum / count : (fDs.isNotEmpty ? fDs.first : 0.0);
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

  /// Short badge label for the cover page.
  static String _shortTestName(TestType t) => switch (t) {
        TestType.cmj       => 'CMJ',
        TestType.cmjArms   => 'CMJ + BRAZOS',
        TestType.sj        => 'SJ',
        TestType.dropJump  => 'DROP JUMP',
        TestType.multiJump => 'MULTI-SALTO',
        TestType.cop       => 'EQUILIBRIO (CoP)',
        TestType.imtp      => 'IMTP',
        TestType.freeTest  => 'TEST LIBRE',
      };

  static String _fmtDate(DateTime dt) {
    final d  = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final h  = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$d/$mo/${dt.year}  $h:$mi';
  }

  /// Formats a date in Spanish for the cover page.
  /// e.g. "20 de marzo de 2026"
  static String _fmtDateSpanish(DateTime dt) {
    final mes = _meses[dt.month];
    return '${dt.day} de $mes de ${dt.year}';
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

// ── Internal helper types ──────────────────────────────────────────────────

class _NormLevel {
  final String label;
  final double min;
  final double max;
  final PdfColor color;
  const _NormLevel(this.label, this.min, this.max, this.color);
}

class _Recommendation {
  final String icon;
  final PdfColor color;
  final String text;
  const _Recommendation({
    required this.icon,
    required this.color,
    required this.text,
  });
}
