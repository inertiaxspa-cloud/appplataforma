/// Firmware format versions understood by [CsvParser].
enum FirmwareVersion { v1Legacy, v23 }

/// Parsed line directly from firmware v2.3 RECEPTOR CSV output.
class RawSample {
  final int timestampUs;
  final int platformId;      // 1 = Platform A (left), 2 = Platform B (right)
  final int seqNum;
  final int adcMasterL;
  final int adcMasterR;
  final int adcSlaveL;
  final int adcSlaveR;
  final int flags;           // FLAG_SLAVE_TIMEOUT = 0x01
  final int seqJump;
  final int packetsLostTotal;
  final FirmwareVersion firmwareVersion;

  const RawSample({
    required this.timestampUs,
    required this.platformId,
    required this.seqNum,
    required this.adcMasterL,
    required this.adcMasterR,
    required this.adcSlaveL,
    required this.adcSlaveR,
    required this.flags,
    required this.seqJump,
    required this.packetsLostTotal,
    this.firmwareVersion = FirmwareVersion.v23,
  });

  bool get hasSlaveTimeout => (flags & 0x01) != 0;

  /// Effective slave channels: zeroed when SLAVE_TIMEOUT flag is set.
  int get effectiveSlaveL => hasSlaveTimeout ? 0 : adcSlaveL;
  int get effectiveSlaveR => hasSlaveTimeout ? 0 : adcSlaveR;

  /// Combined raw left reading (negated per firmware convention).
  /// With 1 platform: rawLeft represents the MASTER-board side.
  int get rawLeft  => -(adcMasterL + effectiveSlaveL);

  /// Combined raw right reading (negated per firmware convention).
  /// With 1 platform: rawRight represents the SLAVE-board side.
  int get rawRight => -(adcMasterR + effectiveSlaveR);

  /// Sum of master board channels (for single-platform asymmetry).
  int get rawMasterSide => -(adcMasterL + adcMasterR);

  /// Sum of slave board channels (for single-platform asymmetry).
  int get rawSlaveSide  => hasSlaveTimeout ? 0 : -(adcSlaveL + adcSlaveR);
}
