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

  /// ESP32 ROM bootloader output prefixes that should be silently discarded.
  /// These lines appear on every DTR reset and pollute the parser.
  static const List<String> _bootloaderPrefixes = [
    'rst:',       // reset reason
    'ets ',       // ROM boot banner
    'load:',      // partition load
    'entry ',     // firmware entry point
    'SPIWP:',     // flash config
    'clk_drv:',   // clock driver
    'mode:',      // boot mode
    'ho ',        // hardware options
    'tail ',      // tail chunk
    'chksum',     // checksum
  ];

  RawSample? parse(String line) {
    // Too short to be a real sample (smallest legacy: "A;0;1;1" = 7 chars)
    if (line.length < 5) return null;
    // Reject lines containing Unicode replacement char (binary garbage decoded)
    if (line.contains('\uFFFD')) return null;
    // Skip debug lines from firmware ([RX], [P1], etc.)
    if (line.startsWith('[')) return null;
    // Skip CSV header line
    if (line.startsWith('timestamp')) return null;
    // Skip ESP32 bootloader noise
    for (final prefix in _bootloaderPrefixes) {
      if (line.startsWith(prefix)) return null;
    }
    // Cheap substring check for common bootloader pattern
    if (line.contains('boot:0x')) return null;

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
      } catch (e) {
        assert(() { print('[CsvParser] Legacy parse error: $e'); return true; }());
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
    } catch (e) {
      assert(() { print('[CsvParser] v2.3 parse error: $e'); return true; }());
      return null;
    }
  }
}
