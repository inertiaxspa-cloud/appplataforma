class PhysicsConstants {
  PhysicsConstants._();

  static const double gravity          = 9.81;    // m/s²
  static const int    samplingRateHz   = 1000;    // Hz
  static const int    baudRate         = 921600;
  static const int    smoothingWindow  = 35;      // samples (~35ms)

  // Platform auto-detection timeout
  static const int    platformBTimeoutMs = 500;

  // Phase detection thresholds (match Python app.py)
  static const double settleDurationS    = 1.5;
  static const double cmjWeightThreshold = 80.0;  // N delta for unweighting start
  static const double stdThreshold       = 3.0;   // N std for "at rest"
  static const double flightThreshold    = 20.0;  // N below BW = airborne
  static const double landingThreshold   = 80.0;  // N above BW = landed
  static const double imtpPlateauN       = 10.0;  // N/s slope for IMTP plateau

  // Dynamic flight/landing thresholds as % of body weight (match Python app.py)
  static const double flightThresholdFactor  = 0.12;  // 12% BW
  static const double landingThresholdFactor = 0.30;  // 30% BW

  // Platform physical dimensions (default 400x600mm, adjustable in settings)
  static const double platformWidthMm   = 400.0;
  static const double platformLengthMm  = 600.0;

  // RFD windows
  static const double rfdWindow50ms     = 0.050;
  static const double rfdWindow100ms    = 0.100;
  static const double rfdWindow200ms    = 0.200;

  // Chart
  static const int    chartWindowS      = 5;      // seconds visible in live chart
  static const int    chartBufferSize   = chartWindowS * samplingRateHz;

  // CoP
  static const double copChi2At95       = 5.991;  // χ²(0.95, df=2)
}
