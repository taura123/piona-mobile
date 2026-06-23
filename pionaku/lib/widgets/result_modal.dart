import 'package:flutter/material.dart';

import '../screens/scan_screen.dart';
import '../theme/app_theme.dart';

/// Aksi saat sheet hasil scan ditutup (partial).
enum ScanResultSheetAction {
  /// Tutup dan lanjut scan.
  closed,

  /// Buka Manual Entry untuk melengkapi draft.
  openManualEntry,
}

/// Modal hasil scan:
/// - complete: hijau (berhasil & lengkap)
/// - partial: kuning (berhasil scan, tapi data tidak lengkap) + CTA Manual Entry
/// - failed: merah (gagal parse)
class ResultModal extends StatelessWidget {
  const ResultModal({
    super.key,
    required this.status,
    this.barcodeValue,
  });

  final ParseStatus status;
  final String? barcodeValue;

  @override
  Widget build(BuildContext context) {
    final ParseStatus s = status;

    final Color bgColor;
    final Color accentColor;
    final String title;
    final String message;
    final IconData icon;

    if (s == ParseStatus.complete) {
      bgColor = AppTheme.validGreenLight;
      accentColor = AppTheme.validGreen;
      title = 'Berhasil';
      message = 'Scan berhasil dan data lengkap.';
      icon = Icons.check_circle;
    } else if (s == ParseStatus.partial) {
      bgColor = const Color(0xFFFFF8E1);
      accentColor = const Color(0xFFF59E0B);
      title = 'Berhasil Scan';
      message =
          'Data tidak lengkap. Draft sudah disimpan — lengkapi di Manual Entry, '
          'lalu Publish agar tersimpan ke server.';
      icon = Icons.warning_amber_rounded;
    } else {
      bgColor = AppTheme.invalidRedLight;
      accentColor = AppTheme.invalidRed;
      title = 'Gagal';
      message = 'Format barcode tidak dikenali atau data BCBP tidak valid.';
      icon = Icons.cancel;
    }

    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 56, color: accentColor),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.textSecondaryColor(context),
                height: 1.4,
              ),
            ),
            if (s == ParseStatus.partial) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surface(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.borderColor(context),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 22,
                      color: accentColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status sinkron',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimaryColor(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Draft ada di perangkat. Belum masuk daftar penumpang '
                            'server sampai di Publish dari Manual Entry.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: AppTheme.textSecondaryColor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (barcodeValue != null && barcodeValue!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  barcodeValue!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimaryColor(context),
                    fontFamily: 'monospace',
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 28),
            if (s == ParseStatus.partial) ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.of(context)
                      .pop(ScanResultSheetAction.openManualEntry),
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusButton),
                    ),
                  ),
                  child: const Text(
                    'Lanjut ke Manual Entry',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(ScanResultSheetAction.closed),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimaryColor(context),
                    side: BorderSide(color: AppTheme.borderColor(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusButton),
                    ),
                  ),
                  child: const Text('Tutup (draft tersimpan)'),
                ),
              ),
            ] else
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(ScanResultSheetAction.closed),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusButton),
                    ),
                  ),
                  child: const Text('Tutup'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
