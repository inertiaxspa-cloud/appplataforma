import '../../data/models/raw_sample.dart';

/// Parses a single CSV line from the firmware.
///
/// **Firmware v2.3** format (10 columns, comma-separated):
///   timestamp_us,platform_id,seq_num,adc_master_L,adc_master_R,
///   adc_slave_L,adc_slave_R,flags,seq_jump,packets_lost_total
///
/// **Legacy (app.py)** format (semicolon-separated, first field 'A' or 'B'):
///   A;anyfield;adc_L;adc_R
///   B;anyfield;adc_L;adc_R
///
/// Debug / header lines are rejected by returning null.
class CsvParser {
  static const int _minColumns = 8;

  RawSample? parse(String line) {
    // Skip debug lines from firmware ([RX], [P1], etc.)
    if (line.startsWith('[')) return null;
    // Skip CSV header line
    if (line.startsWith('timestamp')) return null;

    // ── Legacy format: semicolon-separated, first field is 'A' or 'B' ────────
    if (line.contains(';')) {
      final parts = line.split(';');
      if (parts.length < 4) return null;
      final id = parts[0].trim();
      if (id != 'A' && id != 'B') return null;

      try {
        final platformId = id == 'A' ? 1 : 2;
        final adcMasterL = -int.parse(parts[parts.length - 2].trim());
        final adcMasterR = -int.parse(parts.last.trim());

        return RawSample(
          timestampUs: 0,
          platformId: platformId,
          seqNum: 0,
          adcMasterL: adcMasterL,
          adcMasterR: adcMasterR,
          adcSlaveL: 0,
          adcSlaveR: 0,
          flags: 0,
          seqJump: 0,
          packetsLostTotal: 0,
          firmwareVersion: FirmwareVersion.v1Legacy,
        );
      } catch (_) {
        return null;
      }
    }

    // ── Firmware v2.3 format: comma-separated ─────────────────────────────────
    if (!line.contains(',')) return null;

    final parts = line.split(',');
    if (parts.length < _minColumns) return null;

    try {
      final platformId  = int.parse(parts[1].trim());
      if (platformId != 1 && platformId != 2) return null;

      final timestampUs = int.parse(parts[0].trim());
      final seqNum      = int.parse(parts[2].trim());
      final masterL     = int.parse(parts[3].trim());
      final masterR     = int.parse(parts[4].trim());
      final slaveL      = int.parse(parts[5].trim());
      final slaveR      = int.parse(parts[6].trim());

      final flagsStr = parts[7].trim();
      final flags = flagsStr.startsWith('0x') || flagsStr.startsWith('0X')
          ? int.parse(flagsStr.substring(2), radix: 16)
          : int.parse(flagsStr);

      final seqJump          = parts.length > 8 ? int.tryParse(parts[8].trim()) ?? 0 : 0;
      final packetsLostTotal = parts.length > 9 ? int.tryParse(parts[9].trim()) ?? 0 : 0;

      return RawSample(
        timestampUs: timestampUs,
        platformId: platformId,
        seqNum: seqNum,
        adcMasterL: masterL,
        adcMasterR: masterR,
        adcSlaveL: slaveL,
        adcSlaveR: slaveR,
        flags: flags,
        seqJump: seqJump,
        packetsLostTotal: packetsLostTotal,
        firmwareVersion: FirmwareVersion.v23,
      );
    } catch (_) {
      return null;
    }
  }
}
