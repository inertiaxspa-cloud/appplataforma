import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

// ── Data model ─────────────────────────────────────────────────────────────

class TutorialStep {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<String> tips;

  const TutorialStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.tips = const [],
  });
}

class TestTutorial {
  final String testName;
  final String testAcronym;
  final String objective;
  final String whatItMeasures;
  final List<TutorialStep> steps;

  const TestTutorial({
    required this.testName,
    required this.testAcronym,
    required this.objective,
    required this.whatItMeasures,
    required this.steps,
  });
}

// ── Tutorial content ───────────────────────────────────────────────────────

class TestTutorials {
  static const cmj = TestTutorial(
    testName: 'Salto con Contramovimiento',
    testAcronym: 'CMJ',
    objective: 'Medir tu potencia y altura de salto con impulso natural',
    whatItMeasures:
        'Potencia explosiva del tren inferior, altura de salto, simetría y velocidad de generación de fuerza (RFD)',
    steps: [
      TutorialStep(
        title: 'Posición inicial',
        description:
            'Párate sobre la plataforma con los pies al ancho de tus hombros. Brazos a los costados o manos en las caderas.',
        icon: Icons.accessibility_new_rounded,
        color: Color(0xFF2196F3),
        tips: [
          'Pies paralelos, puntas levemente hacia afuera',
          'Peso bien distribuido en ambos pies',
        ],
      ),
      TutorialStep(
        title: 'Fase de bajada',
        description:
            'Baja rápido en una sentadilla parcial — este impulso previo es lo que diferencia el CMJ del SJ.',
        icon: Icons.arrow_downward_rounded,
        color: Color(0xFFFF9800),
        tips: [
          'La bajada debe ser rápida y continua',
          'No hagas pausa entre la bajada y el salto',
        ],
      ),
      TutorialStep(
        title: '¡Salta!',
        description:
            'Inmediatamente después de la bajada, salta con toda tu fuerza. Extiende completamente piernas y tobillos.',
        icon: Icons.arrow_upward_rounded,
        color: Color(0xFF4CAF50),
        tips: [
          'No detengas el movimiento entre bajada y salto',
          'Estira completamente las piernas al despegar',
        ],
      ),
      TutorialStep(
        title: 'Aterrizaje',
        description:
            'Cae con ambos pies al mismo tiempo sobre la plataforma, en la posición inicial. Amortiza con las rodillas.',
        icon: Icons.sports_gymnastics,
        color: Color(0xFF9C27B0),
        tips: [
          'Aterriza con ambos pies simultáneos',
          'Dobla las rodillas al caer para amortiguar',
        ],
      ),
    ],
  );

  static const sj = TestTutorial(
    testName: 'Salto en Sentadilla',
    testAcronym: 'SJ',
    objective:
        'Medir la fuerza pura de piernas sin usar el impulso del contramovimiento',
    whatItMeasures:
        'Fuerza concéntrica pura del tren inferior. Comparar CMJ vs SJ revela tu capacidad de reutilización elástica del tendón.',
    steps: [
      TutorialStep(
        title: 'Posición inicial',
        description:
            'Párate sobre la plataforma con pies al ancho de hombros.',
        icon: Icons.accessibility_new_rounded,
        color: Color(0xFF2196F3),
        tips: ['Posición igual que el CMJ para poder comparar'],
      ),
      TutorialStep(
        title: 'Baja a sentadilla y detente',
        description:
            'Desciende lentamente hasta que la rodilla forme un ángulo recto (como sentarte en una silla). Mantén esta posición quieta 2-3 segundos.',
        icon: Icons.arrow_downward_rounded,
        color: Color(0xFFFF9800),
        tips: [
          'Mantén la posición quieta 2-3 segundos',
          'Espalda recta, rodillas alineadas con los pies',
          'NO te muevas antes de saltar — invalida el test',
        ],
      ),
      TutorialStep(
        title: '¡Salta desde posición estática!',
        description:
            'Sin hacer ningún movimiento previo hacia arriba, salta con toda tu fuerza desde la posición de sentadilla.',
        icon: Icons.arrow_upward_rounded,
        color: Color(0xFF4CAF50),
        tips: [
          'No hay impulso previo — solo fuerza pura',
          'Si subes aunque sea un poco antes, el test no es válido',
        ],
      ),
      TutorialStep(
        title: 'Aterrizaje',
        description: 'Cae con ambos pies al mismo tiempo sobre la plataforma.',
        icon: Icons.sports_gymnastics,
        color: Color(0xFF9C27B0),
        tips: ['Aterriza con ambos pies simultáneos'],
      ),
    ],
  );

  static const dj = TestTutorial(
    testName: 'Salto desde Caída',
    testAcronym: 'DJ',
    objective:
        'Medir la capacidad reactiva y el ciclo de estiramiento-acortamiento muscular',
    whatItMeasures:
        'Índice RSI (eficiencia reactiva), tiempo de contacto y altura. Evalúa la capacidad de rebotar rápido desde el suelo.',
    steps: [
      TutorialStep(
        title: 'Elige la altura del cajón',
        description:
            'Selecciona la altura del cajón en la app (20-60 cm). Párate en el borde con los pies juntos.',
        icon: Icons.straighten_rounded,
        color: Color(0xFF2196F3),
        tips: [
          'Empieza con 20-30 cm si es la primera vez',
          'Pies juntos al borde del cajón',
        ],
      ),
      TutorialStep(
        title: 'Caída — no saltes',
        description:
            'Da un paso hacia adelante y deja que la gravedad te lleve al suelo. NO saltes desde el cajón.',
        icon: Icons.arrow_downward_rounded,
        color: Color(0xFFFF9800),
        tips: [
          'Es una caída natural, no un salto',
          'No impulses hacia adelante ni hacia atrás',
        ],
      ),
      TutorialStep(
        title: '¡Rebota inmediatamente!',
        description:
            'Al tocar la plataforma con AMBOS pies simultáneos, salta inmediatamente con máxima explosividad. Minimiza el tiempo en el suelo.',
        icon: Icons.bolt_rounded,
        color: Color(0xFF4CAF50),
        tips: [
          'El contacto debe ser brevísimo',
          'Imagina que el suelo quema',
          'No te quedes agachado al contactar',
        ],
      ),
      TutorialStep(
        title: 'Clave: el RSI',
        description:
            'El RSI mide tu eficiencia reactiva. Un RSI alto significa que saltas alto con muy poco tiempo en el suelo.',
        icon: Icons.speed_rounded,
        color: Color(0xFF9C27B0),
        tips: [
          'RSI > 2.0 es muy bueno para la mayoría de deportistas',
          'Practica aterrizar y saltar sin pausa',
        ],
      ),
    ],
  );

  static const multiJump = TestTutorial(
    testName: 'Saltos Repetidos',
    testAcronym: 'RSI Multi',
    objective:
        'Evaluar la resistencia explosiva y la capacidad reactiva en saltos continuos',
    whatItMeasures:
        'RSI promedio en múltiples saltos, fatiga entre saltos, consistencia y altura media.',
    steps: [
      TutorialStep(
        title: 'Posición inicial',
        description:
            'Párate sobre la plataforma con pies al ancho de hombros. Presiona Iniciar cuando estés listo.',
        icon: Icons.accessibility_new_rounded,
        color: Color(0xFF2196F3),
      ),
      TutorialStep(
        title: 'Salta de forma continua',
        description:
            'Realiza saltos continuos, uno tras otro, lo más alto y rápido posible. La app detecta cada salto automáticamente.',
        icon: Icons.repeat_rounded,
        color: Color(0xFFFF9800),
        tips: [
          'Salta lo más alto posible en cada salto',
          'La app detecta cada salto automáticamente',
        ],
      ),
      TutorialStep(
        title: 'Minimiza el contacto',
        description:
            'El objetivo es estar el mínimo tiempo posible en el suelo entre saltos. Rebota como una pelota.',
        icon: Icons.bolt_rounded,
        color: Color(0xFF4CAF50),
        tips: [
          'Mínimo tiempo en el suelo',
          'No te agaches mucho entre saltos',
          'Mantén el ritmo constante',
        ],
      ),
      TutorialStep(
        title: 'Finaliza el test',
        description:
            'Realiza entre 5 y 10 saltos continuos. Presiona Detener cuando termines.',
        icon: Icons.timer_rounded,
        color: Color(0xFF9C27B0),
        tips: [
          '5 saltos → potencia explosiva',
          '10 saltos → resistencia reactiva',
        ],
      ),
    ],
  );

  static const imtp = TestTutorial(
    testName: 'Tracción Isométrica',
    testAcronym: 'IMTP',
    objective:
        'Medir la fuerza máxima y la velocidad de desarrollo de fuerza sin movimiento',
    whatItMeasures:
        'Fuerza máxima (N) y RFD en 50/100/200ms. Evalúa fuerza máxima y explosividad sin desplazamiento articular.',
    steps: [
      TutorialStep(
        title: 'Configura el equipo',
        description:
            'La barra debe quedar a la altura del muslo medio (entre rodilla y cadera). Ajústala antes del test.',
        icon: Icons.settings_rounded,
        color: Color(0xFF2196F3),
        tips: [
          'Altura de barra: mitad del muslo',
          'Ajusta antes de que el atleta suba a la plataforma',
        ],
      ),
      TutorialStep(
        title: 'Posición del atleta',
        description:
            'Párate sobre la plataforma con rodillas levemente flexionadas y espalda recta. Agarra firmemente la barra con ambas manos.',
        icon: Icons.accessibility_new_rounded,
        color: Color(0xFFFF9800),
        tips: [
          'Espalda recta y neutra durante todo el test',
          'Agarre cómodo y firme en la barra',
          'Rodilla levemente doblada — no completamente extendida',
        ],
      ),
      TutorialStep(
        title: '¡Tira con máxima fuerza!',
        description:
            'Al indicar el sistema, TIRA de la barra hacia arriba con la MÁXIMA fuerza posible. La barra no se moverá — es isométrico.',
        icon: Icons.fitness_center_rounded,
        color: Color(0xFF4CAF50),
        tips: [
          'La barra no se mueve — es completamente normal',
          'Concéntrate en EMPUJAR el suelo hacia abajo',
          'Tira lo más fuerte que puedas desde el primer instante',
        ],
      ),
      TutorialStep(
        title: 'Mantén la fuerza',
        description:
            'Mantén la fuerza máxima durante 3-5 segundos. El sistema detecta automáticamente el pico y finaliza el test.',
        icon: Icons.timer_rounded,
        color: Color(0xFF9C27B0),
        tips: [
          'No sueltes hasta que el sistema lo indique',
          'Mantén el esfuerzo máximo durante toda la contracción',
        ],
      ),
    ],
  );

  static const cop = TestTutorial(
    testName: 'Test de Equilibrio',
    testAcronym: 'CoP',
    objective: 'Evaluar el control postural y el equilibrio estático',
    whatItMeasures:
        'Área de oscilación del centro de presión (CoP), velocidad de balanceo y frecuencia. Detecta déficits de estabilidad.',
    steps: [
      TutorialStep(
        title: 'Configura el test',
        description:
            'Selecciona la postura (ambos pies / pie izquierdo / pie derecho) y si los ojos estarán abiertos o cerrados.',
        icon: Icons.tune_rounded,
        color: Color(0xFF2196F3),
        tips: [
          'Empieza siempre con ambos pies y ojos abiertos',
          'Más difícil: un pie con ojos cerrados',
        ],
      ),
      TutorialStep(
        title: 'Posición inicial',
        description:
            'Párate sobre la plataforma en la postura elegida. Si los ojos están abiertos, fija la mirada en un punto al frente.',
        icon: Icons.accessibility_new_rounded,
        color: Color(0xFFFF9800),
        tips: [
          'Pies paralelos para postura bipodal',
          'Mira a un punto fijo en la pared',
          'Brazos relajados a los costados',
        ],
      ),
      TutorialStep(
        title: 'Mantén la posición quieta',
        description:
            'Al presionar Iniciar, permanece lo más quieto posible durante 30 segundos. No hagas movimientos voluntarios.',
        icon: Icons.hourglass_empty_rounded,
        color: Color(0xFF4CAF50),
        tips: [
          'Respira con normalidad',
          'No corrijas el equilibrio con movimientos grandes',
          'Si pierdes el equilibrio, vuelve a la posición y continúa',
        ],
      ),
      TutorialStep(
        title: 'Interpretación del resultado',
        description:
            'Menor área de oscilación = mejor equilibrio. El índice Romberg compara ojos abiertos vs cerrados para evaluar dependencia visual.',
        icon: Icons.analytics_rounded,
        color: Color(0xFF9C27B0),
        tips: [
          'Área pequeña = buen control postural',
          'Si el área aumenta mucho con ojos cerrados → alta dependencia visual',
        ],
      ),
    ],
  );
}

// ── Public API ─────────────────────────────────────────────────────────────

void showTestTutorial(BuildContext context, TestTutorial tutorial) {
  showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _TutorialDialog(tutorial: tutorial),
  );
}

// ── Dialog widget ──────────────────────────────────────────────────────────

class _TutorialDialog extends StatefulWidget {
  final TestTutorial tutorial;
  const _TutorialDialog({required this.tutorial});

  @override
  State<_TutorialDialog> createState() => _TutorialDialogState();
}

class _TutorialDialogState extends State<_TutorialDialog>
    with TickerProviderStateMixin {
  late final PageController _page;
  late final AnimationController _iconAnim;
  late final Animation<double> _iconScale;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _page = PageController();
    _iconAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _iconScale =
        CurvedAnimation(parent: _iconAnim, curve: Curves.elasticOut);
    _iconAnim.forward();
  }

  @override
  void dispose() {
    _page.dispose();
    _iconAnim.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.tutorial.steps.length) return;
    _page.animateToPage(index,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    _iconAnim.reset();
    _iconAnim.forward();
    setState(() => _current = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final steps  = widget.tutorial.steps;
    final isLast = _current == steps.length - 1;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Header bar ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              color: AppColors.primary,
              child: Row(children: [
                const Icon(Icons.school_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tutorial — ${widget.tutorial.testAcronym}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      Text(widget.tutorial.testName,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
            ),

            // ── "Qué mide" strip ────────────────────────────────────────
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              color: AppColors.primary.withAlpha(18),
              child: Text(
                '📊 Mide: ${widget.tutorial.whatItMeasures}',
                style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withAlpha(170),
                    height: 1.4),
              ),
            ),

            // ── Steps PageView ───────────────────────────────────────────
            Flexible(
              child: PageView.builder(
                controller: _page,
                itemCount: steps.length,
                onPageChanged: (i) {
                  _iconAnim.reset();
                  _iconAnim.forward();
                  setState(() => _current = i);
                },
                itemBuilder: (_, i) => _StepPage(
                  step: steps[i],
                  stepNumber: i + 1,
                  totalSteps: steps.length,
                  iconScale: _iconScale,
                ),
              ),
            ),

            // ── Dot indicators ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(steps.length, (i) {
                  return GestureDetector(
                    onTap: () => _goTo(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _current == i ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _current == i
                            ? AppColors.primary
                            : AppColors.primary.withAlpha(55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // ── Navigation buttons ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(children: [
                if (_current > 0) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.arrow_back_rounded, size: 15),
                      label: const Text('Anterior'),
                      onPressed: () => _goTo(_current - 1),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    icon: Icon(
                        isLast
                            ? Icons.check_circle_outline_rounded
                            : Icons.arrow_forward_rounded,
                        size: 16),
                    label: Text(isLast ? '¡Listo para el test!' : 'Siguiente'),
                    onPressed: isLast
                        ? () => Navigator.of(context).pop()
                        : () => _goTo(_current + 1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isLast ? AppColors.success : AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single step page ───────────────────────────────────────────────────────

class _StepPage extends StatelessWidget {
  final TutorialStep step;
  final int stepNumber;
  final int totalSteps;
  final Animation<double> iconScale;

  const _StepPage({
    required this.step,
    required this.stepNumber,
    required this.totalSteps,
    required this.iconScale,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Step chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: step.color.withAlpha(30),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: step.color.withAlpha(100)),
            ),
            child: Text('PASO $stepNumber DE $totalSteps',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: step.color,
                    letterSpacing: 0.5)),
          ),
          const SizedBox(height: 16),

          // Animated icon
          Center(
            child: ScaleTransition(
              scale: iconScale,
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: step.color.withAlpha(22),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: step.color.withAlpha(70), width: 2),
                ),
                child: Icon(step.icon, size: 56, color: step.color),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text(step.title,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface)),
          const SizedBox(height: 8),

          // Description
          Text(step.description,
              style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withAlpha(195),
                  height: 1.55)),

          // Tips
          if (step.tips.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...step.tips.map((tip) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.tips_and_updates_outlined,
                          size: 14, color: step.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(tip,
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface
                                    .withAlpha(175),
                                height: 1.4)),
                      ),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
