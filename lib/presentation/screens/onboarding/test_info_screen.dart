import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../theme/app_theme.dart';

// ── Test metadata model ─────────────────────────────────────────────────────

class _TestInfo {
  final String title;
  final String subtitle;
  final String description;
  final List<String> metrics;
  final List<String> protocol;
  final Color color;
  final IconData icon;

  const _TestInfo({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.metrics,
    required this.protocol,
    required this.color,
    required this.icon,
  });
}

const _infos = <String, _TestInfo>{
  'cmj': _TestInfo(
    title: 'CMJ',
    subtitle: 'Salto con Contramovimiento',
    description:
        'Mide la capacidad de producir fuerza rápidamente usando el ciclo '
        'estiramiento-acortamiento (SSC). El atleta realiza un descenso rápido '
        'seguido de un salto explosivo, aprovechando la energía elástica almacenada '
        'en tendones y músculos.',
    metrics: [
      'Altura de salto (cm)',
      'Potencia pico (W/kg)',
      'Impulso neto (N·s)',
      'Fase de descenso — RFD (N/s)',
      'Asimetría bilateral (%)',
      'RSI modificado',
    ],
    protocol: [
      '1. Atleta de pie sobre la plataforma, manos en las caderas.',
      '2. Descender rápido hasta ~90° de flexión de rodilla.',
      '3. Saltar con máxima explosividad.',
      '4. Aterrizar sobre la misma plataforma con rodillas semiflexionadas.',
    ],
    color: AppColors.primary,
    icon: Icons.arrow_upward_rounded,
  ),
  'sj': _TestInfo(
    title: 'SJ',
    subtitle: 'Salto sin Contramovimiento',
    description:
        'Evalúa la fuerza concéntrica pura partiendo desde posición estática '
        '(sin contramovimiento previo). Elimina la contribución del ciclo '
        'estiramiento-acortamiento, reflejando la capacidad de producción de '
        'fuerza concéntrica aislada.',
    metrics: [
      'Altura de salto (cm)',
      'Potencia pico concéntrica (W/kg)',
      'Impulso concéntrico (N·s)',
      'Déficit CMJ–SJ (%)',
      'Asimetría bilateral (%)',
    ],
    protocol: [
      '1. Atleta en posición de sentadilla ~90°, manos en caderas.',
      '2. Mantener la posición sin moverse durante 2 segundos.',
      '3. Saltar con máxima explosividad desde la posición estática.',
      '4. Sin descenso previo ni contramovimiento.',
    ],
    color: AppColors.forceRight,
    icon: Icons.sports_rounded,
  ),
  'dj': _TestInfo(
    title: 'Drop Jump',
    subtitle: 'Salto desde Caída',
    description:
        'Mide la capacidad reactiva y el RSI (Reactive Strength Index). El atleta '
        'cae desde una altura, contacta brevemente el suelo y salta de inmediato '
        'con máxima altura. Evalúa la rigidez muscular y la eficiencia del ciclo '
        'estiramiento-acortamiento rápido.',
    metrics: [
      'RSI — Reactive Strength Index',
      'Altura de salto (cm)',
      'Tiempo de contacto (ms)',
      'Potencia reactiva (W/kg)',
      'Asimetría de contacto (%)',
    ],
    protocol: [
      '1. Atleta sobre un cajón a la altura indicada (ej. 30 cm).',
      '2. Caer sobre la plataforma sin saltar desde el cajón.',
      '3. Minimizar el tiempo de contacto y maximizar la altura de rebote.',
      '4. Mantener manos en caderas durante todo el salto.',
    ],
    color: AppColors.warning,
    icon: Icons.download_rounded,
  ),
  'multijump': _TestInfo(
    title: 'Multi-Salto',
    subtitle: 'Saltos Consecutivos',
    description:
        'Evalúa la resistencia a la fatiga y la consistencia entre saltos '
        'repetidos. Permite analizar el decaimiento del rendimiento a lo largo '
        'de la serie y la capacidad del atleta de mantener potencia y simetría '
        'bajo fatiga.',
    metrics: [
      'Altura promedio (cm)',
      'Mejor / peor salto (cm)',
      'Índice de fatiga (%)',
      'RSI promedio',
      'Consistencia entre saltos (CV%)',
      'Evolución de asimetría',
    ],
    protocol: [
      '1. Atleta de pie sobre la plataforma, manos en caderas.',
      '2. Realizar saltos CMJ continuos sin pausas.',
      '3. Número de repeticiones según protocolo (ej. 5, 10 o 20 saltos).',
      '4. Aterrizar y rebotar inmediatamente en cada repetición.',
    ],
    color: AppColors.secondary,
    icon: Icons.repeat_rounded,
  ),
  'imtp': _TestInfo(
    title: 'IMTP',
    subtitle: 'Tracción Isométrica a Media Altura',
    description:
        'Mide la fuerza máxima isométrica y la tasa de desarrollo de fuerza (RFD). '
        'El atleta ejerce tracción máxima sobre una barra fija mientras se registra '
        'la curva de fuerza en el tiempo. Es el patrón oro para evaluar la fuerza '
        'máxima sin fatiga dinámica.',
    metrics: [
      'Fuerza pico (N y N/kg)',
      'RFD — Rate of Force Development (N/s)',
      'Impulso a 100, 200 y 300 ms',
      'Asimetría bilateral (%)',
      'Tiempo hasta fuerza pico (ms)',
    ],
    protocol: [
      '1. Ajustar la barra a altura de posición media de IMTP (~95–100° de rodilla).',
      '2. Atleta en posición isométrica, agarre prono sobre la barra.',
      '3. A la señal, aplicar fuerza máxima rápidamente y mantener 5 segundos.',
      '4. Repetir 2–3 intentos con 3 min de descanso entre ellos.',
    ],
    color: AppColors.danger,
    icon: Icons.fitness_center_rounded,
  ),
  'cop': _TestInfo(
    title: 'CoP',
    subtitle: 'Centro de Presión',
    description:
        'Evalúa el equilibrio y el control postural en condiciones estáticas. '
        'Registra el desplazamiento del Centro de Presión (CoP) en el plano '
        'horizontal, calculando métricas de estabilidad como velocidad media, '
        'área de oscilación y frecuencias de movimiento.',
    metrics: [
      'Área de elipse CoP (cm²)',
      'Velocidad media ML y AP (cm/s)',
      'Rango de desplazamiento ML y AP (cm)',
      'Frecuencia media (Hz)',
      'Índice de asimetría bilateral',
    ],
    protocol: [
      '1. Atleta de pie sobre la plataforma, pies a la anchura de caderas.',
      '2. Fijar la mirada en un punto a 2 m de distancia a nivel de ojos.',
      '3. Mantener quietud máxima durante 30 segundos.',
      '4. Repetir con ojos cerrados para evaluar la dependencia vestibular.',
    ],
    color: AppColors.success,
    icon: Icons.accessibility_new_rounded,
  ),
};

// ── Screen ──────────────────────────────────────────────────────────────────

class TestInfoScreen extends StatelessWidget {
  final String testType;

  const TestInfoScreen({super.key, required this.testType});

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final info = _infos[testType.toLowerCase()];

    if (info == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Información del test')),
        body: Center(
          child: Text(
            'Test "$testType" no encontrado.',
            style: TextStyle(color: col.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: col.background,
      appBar: AppBar(
        backgroundColor: col.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: col.textSecondary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          info.title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: col.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: info.color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: info.color.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: info.color.withOpacity(0.15),
                    ),
                    child: Icon(info.icon, color: info.color, size: 28),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    info.subtitle,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: col.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    info.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: col.textSecondary,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            // Metrics section
            _SectionHeader(label: 'MÉTRICAS QUE SE MIDEN'),
            const SizedBox(height: 12),
            ...info.metrics.map(
              (m) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: info.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        m,
                        style: TextStyle(
                          fontSize: 14,
                          color: col.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            // Protocol section
            _SectionHeader(label: 'PROTOCOLO'),
            const SizedBox(height: 12),
            ...info.protocol.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: info.color.withOpacity(0.15),
                      ),
                      child: Center(
                        child: Text(
                          '${entry.key + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: info.color,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 14,
                          color: col.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Dismiss button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: info.color,
                  foregroundColor: Colors.black.withOpacity(0.85),
                  minimumSize: const Size(double.infinity, 52),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Entendido',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: IXTextStyles.sectionHeader(),
    );
  }
}
