import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../services/manual_entry_capture_store.dart';
import '../services/passenger_scan_store.dart';
import '../services/session_context_store.dart';
import '../theme/app_theme.dart';
import '../utils/boarding_pass_ocr_mapper.dart';
import '../utils/bcbp_parser.dart';
import '../utils/on_device_ocr.dart';
import '../widgets/piona_bottom_nav.dart';
import '../widgets/piona_date_picker.dart';

const String _kFlightSchedulePickerClear = '_fsScheduleClear';

enum ManualEntryPhotoFilter { allPhotos, scanNormalPhotos, scanTransitPhotos }
enum ManualEntryStatusFilter { pendingEdit, aiGenerated, completed, trashDeleted }

@immutable
class _AiLoadingState {
  const _AiLoadingState({required this.step, required this.progress});
  final String step;
  final double progress; // 0..1
}

@immutable
class _ZxingPreprocessResult {
  const _ZxingPreprocessResult({this.enhancedPng, this.croppedPng});
  final Uint8List? enhancedPng;
  final Uint8List? croppedPng;
}

// Runs in an isolate via `compute`.
_ZxingPreprocessResult _zxingPreprocessBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return const _ZxingPreprocessResult();

  final resized = img.copyResize(
    decoded,
    width: decoded.width > decoded.height ? 1600 : null,
    height: decoded.height >= decoded.width ? 1600 : null,
    interpolation: img.Interpolation.average,
  );

  final gray = img.grayscale(resized);
  final contrasted = img.contrast(gray, contrast: 140);

  const filter = <num>[
    0, -1, 0,
    -1, 5, -1,
    0, -1, 0,
  ];
  final sharpened =
      img.convolution(contrasted, filter: filter, div: 1, offset: 0);

  final enhancedPng = Uint8List.fromList(img.encodePng(sharpened));

  // Center crop often helps when background noise dominates.
  final w = (sharpened.width * 0.72).round();
  final h = (sharpened.height * 0.72).round();
  final x = ((sharpened.width - w) / 2).round();
  final y = ((sharpened.height - h) / 2).round();
  final cropped = img.copyCrop(sharpened, x: x, y: y, width: w, height: h);
  final croppedPng = Uint8List.fromList(img.encodePng(cropped));

  return _ZxingPreprocessResult(enhancedPng: enhancedPng, croppedPng: croppedPng);
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key, this.asShellBody = false});
  final bool asShellBody;

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  ManualEntryPhotoFilter _photoFilter = ManualEntryPhotoFilter.allPhotos;
  ManualEntryStatusFilter _statusFilter = ManualEntryStatusFilter.pendingEdit;
  DateTime _selectedDate = DateTime.now();
  Timer? _refreshTimer;
  final SessionContextStore _session = SessionContextStore.instance;
  VoidCallback? _sessionListener;

  @override
  void initState() {
    super.initState();
    ManualEntryCaptureStore.instance.addListener(_onStoreChanged);
    _sessionListener = () {
      if (!mounted) return;
      final t = _session.jwtToken?.trim();
      if (t == null || t.isEmpty) return;
      ManualEntryCaptureStore.instance.loadOnce(bearerToken: t, force: true);
      setState(() {});
    };
    _session.addListener(_sessionListener!);

    final token = _session.jwtToken?.trim();
    ManualEntryCaptureStore.instance
        .loadOnce(bearerToken: (token != null && token.isNotEmpty) ? token : null)
        .then((_) {
      if (mounted) setState(() {});
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final t = _session.jwtToken?.trim();
      if (t == null || t.isEmpty) return;
      ManualEntryCaptureStore.instance.loadOnce(bearerToken: t, force: true);
    });
  }

  @override
  void dispose() {
    ManualEntryCaptureStore.instance.removeListener(_onStoreChanged);
    final l = _sessionListener;
    if (l != null) {
      _session.removeListener(l);
      _sessionListener = null;
    }
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  ManualEntryCaptureWorkflowStatus? get _wantStatus => switch (_statusFilter) {
        ManualEntryStatusFilter.pendingEdit =>
          ManualEntryCaptureWorkflowStatus.pending,
        ManualEntryStatusFilter.aiGenerated =>
          ManualEntryCaptureWorkflowStatus.aiGenerated,
        ManualEntryStatusFilter.completed =>
          ManualEntryCaptureWorkflowStatus.completed,
        ManualEntryStatusFilter.trashDeleted =>
          ManualEntryCaptureWorkflowStatus.trash,
      };

  List<ManualEntryCaptureRecord> get _filteredCaptures {
    final ws = _wantStatus;
    final ac = _session.originCode.trim();
    return ManualEntryCaptureStore.instance.records.where((r) {
      if (ac.isNotEmpty && r.airportCode.trim() != ac) return false;
      if (!_sameDay(r.createdAt, _selectedDate)) return false;
      if (ws != null && r.status != ws) return false;
      return switch (_photoFilter) {
        ManualEntryPhotoFilter.allPhotos => true,
        ManualEntryPhotoFilter.scanNormalPhotos =>
          r.source == ManualCaptureScanSource.normal,
        ManualEntryPhotoFilter.scanTransitPhotos =>
          r.source == ManualCaptureScanSource.transit,
      };
    }).toList();
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtDateTimeDetail(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    final sec = d.second.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}, $h.$min.$sec';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(2)} KB';
  }

  String get _summaryLabel {
    final count = _filteredCaptures.length;
    final base = switch (_statusFilter) {
      ManualEntryStatusFilter.pendingEdit => 'Pending',
      ManualEntryStatusFilter.aiGenerated => 'Auto Generated',
      ManualEntryStatusFilter.completed => 'Completed',
      ManualEntryStatusFilter.trashDeleted => 'Trash',
    };
    return '$base ($count)';
  }

  Future<void> _pickDate() async {
    final picked = await showPionaDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (!mounted || picked == null) return;
    setState(() => _selectedDate = picked);
  }

  Future<void> _confirmDelete(ManualEntryCaptureRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Hapus Foto?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text('Hapus "${r.displayFileName}" dari Manual Entry?',
            style: const TextStyle(fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Hapus',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ManualEntryCaptureStore.instance.deleteById(r.id);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  bool _isEmptyField(String v) {
    final s = v.trim();
    return s.isEmpty || s == '—' || s.toLowerCase() == 'n/a';
  }

  int _missingFieldCount(ManualEntryParsedDraft? parsed) {
    if (parsed == null) return 10;
    final fields = <String>[
      parsed.barcodeValue,
      parsed.passengerName,
      parsed.boardingDate,
      parsed.seat,
      parsed.flight,
      parsed.origin,
      parsed.destination,
      parsed.passengerType,
      parsed.category,
      parsed.scanPoint,
    ];
    return fields.where(_isEmptyField).length;
  }

  Future<File?> _writeTempBytes(Uint8List bytes, String name) async {
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/$name');
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }

  Future<List<String>> _buildDecodeCandidates(
    String absPath,
    ValueNotifier<_AiLoadingState>? loading,
  ) async {
    final base = <String>[absPath];
    try {
      loading?.value = const _AiLoadingState(
        step: 'Mempersiapkan foto…',
        progress: 0.18,
      );
      final bytes = await File(absPath).readAsBytes();
      loading?.value = const _AiLoadingState(
        step: 'Meningkatkan kualitas gambar…',
        progress: 0.30,
      );
      final prep = await compute(_zxingPreprocessBytes, bytes);

      loading?.value = const _AiLoadingState(
        step: 'Menyiapkan variasi untuk decoding…',
        progress: 0.42,
      );
      final enhanced = (prep.enhancedPng == null)
          ? null
          : await _writeTempBytes(
              prep.enhancedPng!,
              'manual_entry_zxing_enhanced.png',
            );
      if (enhanced != null) base.add(enhanced.path);

      final croppedFile = (prep.croppedPng == null)
          ? null
          : await _writeTempBytes(
              prep.croppedPng!,
              'manual_entry_zxing_cropped.png',
            );
      if (croppedFile != null) base.add(croppedFile.path);
    } catch (_) {
      // Keep original-only candidate list.
    }
    return base;
  }

  Future<String?> _tryDecodeFromPath(String path, {required bool multi}) async {
    if (multi) {
      final codes = await zx.readBarcodesImagePathString(
        path,
        DecodeParams(
          format: Format.pdf417 | Format.qrCode | Format.code128,
          tryHarder: true,
          tryRotate: true,
          tryInverted: true,
          tryDownscale: true,
          maxSize: 2000,
          isMultiScan: true,
          maxNumberOfSymbols: 10,
        ),
      );
      final valid = codes.codes.where((c) => c.isValid).toList();
      final text = valid.isNotEmpty ? valid.first.text?.trim() : null;
      return (text == null || text.isEmpty) ? null : text;
    }

    final code = await zx.readBarcodeImagePathString(
      path,
      DecodeParams(
        format: Format.any,
        tryHarder: true,
        tryRotate: true,
        tryInverted: true,
        tryDownscale: true,
        maxSize: 2400,
      ),
    );
    final text = code.isValid ? code.text?.trim() : null;
    return (text == null || text.isEmpty) ? null : text;
  }

  Future<String?> _decodeBestEffort(
    String absPath,
    ValueNotifier<_AiLoadingState>? loading,
  ) async {
    final candidates = await _buildDecodeCandidates(absPath, loading);
    for (final p in candidates) {
      try {
        loading?.value = const _AiLoadingState(
          step: 'Mencoba baca barcode (multi-scan)…',
          progress: 0.62,
        );
        final m = await _tryDecodeFromPath(p, multi: true);
        if (m != null) return m;
      } catch (_) {}
      try {
        loading?.value = const _AiLoadingState(
          step: 'Mencoba baca barcode (single-scan)…',
          progress: 0.74,
        );
        final s = await _tryDecodeFromPath(p, multi: false);
        if (s != null) return s;
      } catch (_) {}
    }
    return null;
  }

  bool _hasAnyEssentialFilled(ManualEntryParsedDraft? parsed) {
    if (parsed == null) return false;
    final essentialValues = <String>[
      parsed.barcodeValue,
      parsed.passengerName,
      parsed.flight,
      parsed.origin,
      parsed.destination,
      parsed.boardingDate,
      parsed.seat,
    ];
    return essentialValues.any((v) => !_isEmptyField(v));
  }

  bool _hasAllEssentialFilled(ManualEntryParsedDraft? parsed) {
    if (parsed == null) return false;
    final essentialValues = <String>[
      parsed.barcodeValue,
      parsed.passengerName,
      parsed.flight,
      parsed.origin,
      parsed.destination,
      parsed.boardingDate,
      parsed.seat,
    ];
    return essentialValues.every((v) => !_isEmptyField(v));
  }

  double _essentialConfidence(ManualEntryParsedDraft draft) {
    final essentialValues = <String>[
      draft.barcodeValue,
      draft.passengerName,
      draft.flight,
      draft.origin,
      draft.destination,
      draft.boardingDate,
      draft.seat,
    ];
    final filled = essentialValues.where((v) => !_isEmptyField(v)).length;
    return (filled / essentialValues.length).clamp(0.0, 1.0);
  }

  Future<ManualEntryParsedDraft?> _tryBuildOcrDraft(
    String absPath,
    ValueNotifier<_AiLoadingState> loading,
    ManualEntryCaptureRecord record,
  ) async {
    loading.value = const _AiLoadingState(
      step: 'Barcode gagal, mencoba baca teks (OCR on-device)…',
      progress: 0.80,
    );

    final ocr = await OnDeviceOcr.recognizeTextFromImagePath(absPath);
    final fields = BoardingPassOcrMapper.extractFromTextLines(ocr.lines);

    final category =
        record.source == ManualCaptureScanSource.transit ? 'Transit' : 'Normal';
    final scanPoint =
        record.scanPoint.trim().isEmpty ? 'N/A' : record.scanPoint.trim();

    ManualEntryParsedDraft draftFromFields() {
      return ManualEntryParsedDraft(
        barcodeValue: (fields.pnrOrBarcode ?? '').trim(),
        passengerName: (fields.passengerName ?? '').trim().isEmpty
            ? 'N/A'
            : (fields.passengerName ?? '').trim(),
        boardingDate: (fields.boardingDate ?? '').trim().isEmpty
            ? 'N/A'
            : (fields.boardingDate ?? '').trim(),
        seat: (fields.seat ?? '').trim().isEmpty
            ? 'N/A'
            : (fields.seat ?? '').trim(),
        flight: (fields.flight ?? '').trim().isEmpty
            ? 'N/A'
            : (fields.flight ?? '').trim(),
        origin: (fields.origin ?? '').trim().isEmpty
            ? 'N/A'
            : (fields.origin ?? '').trim(),
        destination: (fields.destination ?? '').trim().isEmpty
            ? 'N/A'
            : (fields.destination ?? '').trim(),
        passengerType: 'Adult',
        category: category,
        scanPoint: scanPoint,
        extractionSource: 'ocr',
        extractionConfidence: fields.confidence,
      );
    }

    final draft = draftFromFields();
    if (!_hasAnyEssentialFilled(draft)) return null;
    return draft;
  }

  Future<void> _showGenerateAiLoading(ValueNotifier<_AiLoadingState> loading) {
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: AppTheme.surface(context),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ValueListenableBuilder<_AiLoadingState>(
                  valueListenable: loading,
                  builder: (context, state, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Generate Otomatis',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textPrimaryColor(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          state.step,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: AppTheme.textSecondaryColor(context),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: state.progress.clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: AppTheme.borderColor(context)
                                .withValues(alpha: 0.45),
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAiGeneratedResultDialog(
    ManualEntryCaptureRecord record, {
    required String title,
    String? subtitle,
  }) async {
    var effectiveRecord = record;
    final parsed = record.parsed;

    final fieldPairs = <(String label, String value)>[
      ('Barcode/PNR', parsed?.barcodeValue ?? ''),
      ('Passenger', parsed?.passengerName ?? ''),
      ('Flight', parsed?.flight ?? ''),
      ('Origin', parsed?.origin ?? ''),
      ('Destination', parsed?.destination ?? ''),
      ('Date', parsed?.boardingDate ?? ''),
      ('Seat', parsed?.seat ?? ''),
      ('Type', parsed?.passengerType ?? ''),
      ('Category', parsed?.category ?? ''),
      ('Scan Point', parsed?.scanPoint ?? ''),
    ];

    // "Penting" = field yang memang ditargetkan untuk diisi otomatis (barcode/OCR).
    // passengerType/category/scanPoint sering diisi default/konteks, jadi tidak dihitung "kebaca dari barcode".
    final essentialPairs = <(String label, String value)>[
      ('Barcode/PNR', parsed?.barcodeValue ?? ''),
      ('Passenger', parsed?.passengerName ?? ''),
      ('Flight', parsed?.flight ?? ''),
      ('Origin', parsed?.origin ?? ''),
      ('Destination', parsed?.destination ?? ''),
      ('Date', parsed?.boardingDate ?? ''),
      ('Seat', parsed?.seat ?? ''),
    ];

    final filledEssential = essentialPairs
        .where((p) => !_isEmptyField(p.$2))
        .map((p) => p.$1)
        .toList();
    final emptyEssential = essentialPairs
        .where((p) => _isEmptyField(p.$2))
        .map((p) => p.$1)
        .toList();

    final noneEssentialRead = filledEssential.isEmpty;
    final allEssentialRead = emptyEssential.isEmpty;

    // Safety: if the result is GREEN, ensure it is stored as Auto Generated.
    // This avoids cases where the UI shows "green" but status remains pending.
    if (allEssentialRead &&
        record.status != ManualEntryCaptureWorkflowStatus.aiGenerated) {
      try {
        effectiveRecord = record.copyWith(
          status: ManualEntryCaptureWorkflowStatus.aiGenerated,
        );
        await ManualEntryCaptureStore.instance.updateById(
          record.id,
          effectiveRecord,
        );
      } catch (_) {
        // If saving fails, still show the dialog.
      }
    }

    final bannerColor = noneEssentialRead
        ? const Color(0xFFE53935)
        : allEssentialRead
            ? const Color(0xFF16A34A)
            : const Color(0xFFF59E0B);
    final bannerBg = bannerColor.withValues(alpha: 0.10);
    final bannerBorder = bannerColor.withValues(alpha: 0.35);
    final bannerIcon = noneEssentialRead
        ? Icons.error_rounded
        : allEssentialRead
            ? Icons.check_circle_rounded
            : Icons.warning_rounded;
    final bannerTitle = noneEssentialRead
        ? 'Tidak ada field terbaca'
        : allEssentialRead
            ? 'Semua field penting terbaca'
            : 'Sebagian field terbaca';
    final bannerMessage = noneEssentialRead
        ? 'Warning merah: tidak ada field penting yang kebaca dari barcode. Silakan isi manual.'
        : allEssentialRead
            ? 'Hijau: hasil sudah lengkap dan tersimpan. Silakan cek kembali sebelum dikirim ke Passenger List.'
            : 'Kuning: ada field yang kebaca, sisanya masih kosong. Silakan lengkapi manual.';

    String listText(List<String> labels) => labels.join(', ');

    Widget row(String label, String value) {
      final empty = _isEmptyField(value);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondaryColor(context),
                ),
              ),
            ),
            Expanded(
              child: Text(
                empty ? '—' : value,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: empty ? FontWeight.w600 : FontWeight.w800,
                  color: empty
                      ? AppTheme.textSecondaryColor(context)
                          .withValues(alpha: 0.85)
                      : AppTheme.textPrimaryColor(context),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppTheme.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: bannerBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: bannerBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(bannerIcon, size: 18, color: bannerColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bannerTitle,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimaryColor(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            bannerMessage,
                            style: TextStyle(
                              fontSize: 12.0,
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
              const SizedBox(height: 12),
              if (!noneEssentialRead) ...[
                Text(
                  'Terisi: ${listText(filledEssential)}',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimaryColor(context),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (!allEssentialRead) ...[
                Text(
                  'Masih kosong: ${listText(emptyEssential)}',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w800,
                    color: bannerColor,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              for (final p in fieldPairs) row(p.$1, p.$2),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Tutup',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          if (!allEssentialRead)
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openEditEntryDialog(effectiveRecord);
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Lanjut Edit',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _runAiGenerated(ManualEntryCaptureRecord record) async {
    final absPath =
        await ManualEntryCaptureStore.instance.fileAbsolutePath(record);
    if (absPath.trim().isEmpty) {
      _showSnack('Entri ini tidak memiliki foto untuk diproses.');
      return;
    }
    final f = File(absPath);
    if (!f.existsSync()) {
      _showSnack('File foto tidak ditemukan. Coba Manual Capture ulang.');
      return;
    }

    if (!mounted) return;
    final loading = ValueNotifier<_AiLoadingState>(
      const _AiLoadingState(step: 'Memulai…', progress: 0.06),
    );
    // Don't await; we close it manually via rootNavigator pop.
    _showGenerateAiLoading(loading);

    ManualEntryParsedDraft fallbackDraft() {
      final existing = record.parsed;
      final category =
          record.source == ManualCaptureScanSource.transit ? 'Transit' : 'Normal';
      final scanPoint =
          record.scanPoint.trim().isEmpty ? 'N/A' : record.scanPoint.trim();
      if (existing != null) {
        return ManualEntryParsedDraft(
          barcodeValue: existing.barcodeValue,
          passengerName: existing.passengerName,
          boardingDate: existing.boardingDate,
          seat: existing.seat,
          flight: existing.flight,
          origin: existing.origin,
          destination: existing.destination,
          passengerType: existing.passengerType,
          category: existing.category.isEmpty ? category : existing.category,
          scanPoint: existing.scanPoint.isEmpty ? scanPoint : existing.scanPoint,
        );
      }
      return ManualEntryParsedDraft(
        barcodeValue: '',
        passengerName: 'N/A',
        boardingDate: 'N/A',
        seat: 'N/A',
        flight: 'N/A',
        origin: 'N/A',
        destination: 'N/A',
        passengerType: 'Adult',
        category: category,
        scanPoint: scanPoint,
      );
    }

    try {
      loading.value = const _AiLoadingState(
        step: 'Membaca barcode dari foto…',
        progress: 0.54,
      );
      final raw = await _decodeBestEffort(absPath, loading);

      if (raw == null || raw.isEmpty) {
        final ocrDraft = await _tryBuildOcrDraft(absPath, loading, record);
        loading.value = const _AiLoadingState(
          step: 'Menyimpan hasil…',
          progress: 0.92,
        );
        final draft = ocrDraft ?? fallbackDraft();
        // MERAH -> tetap pending. Draft tetap disimpan untuk diedit.
        final updated = record.copyWith(
          parsed: draft,
          status: ManualEntryCaptureWorkflowStatus.pending,
        );
        await ManualEntryCaptureStore.instance.updateById(
          record.id,
          updated,
        );
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        await _showAiGeneratedResultDialog(
          updated,
          title: 'Hasil Generate (Tidak Terbaca)',
          subtitle:
              ocrDraft != null
                  ? 'Barcode tidak terbaca. Sistem mencoba OCR on-device dan membuat draft dari teks yang terbaca. Silakan cek & lengkapi manual.'
                  : 'Barcode tidak terbaca dari foto. Draft dibuat agar bisa kamu lengkapi manual.',
        );
        return;
      }

      loading.value = const _AiLoadingState(
        step: 'Mem-parsing BCBP…',
        progress: 0.86,
      );
      final parsed = parseBCBP(raw);
      if (!parsed.isSuccess) {
        final ocrDraft = await _tryBuildOcrDraft(absPath, loading, record);
        loading.value = const _AiLoadingState(
          step: 'Menyimpan hasil…',
          progress: 0.92,
        );
        final draft = ocrDraft ??
            ManualEntryParsedDraft(
              barcodeValue: raw,
              passengerName: 'N/A',
              boardingDate: 'N/A',
              seat: 'N/A',
              flight: 'N/A',
              origin: 'N/A',
              destination: 'N/A',
              passengerType: 'Adult',
              category: record.source == ManualCaptureScanSource.transit
                  ? 'Transit'
                  : 'Normal',
              scanPoint: record.scanPoint.trim().isEmpty
                  ? 'N/A'
                  : record.scanPoint.trim(),
              extractionSource: 'barcode',
              extractionConfidence: 0.25,
            );
        // KUNING (minimal barcode kebaca) -> tetap pending, tapi draft tersimpan
        final updated = record.copyWith(
          parsed: draft,
          status: ManualEntryCaptureWorkflowStatus.pending,
        );
        await ManualEntryCaptureStore.instance.updateById(record.id, updated);
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        await _showAiGeneratedResultDialog(
          updated,
          title: 'Hasil Generate (BCBP Tidak Valid)',
          subtitle:
              ocrDraft != null
                  ? 'Barcode kebaca, tapi format BCBP tidak valid. Sistem juga mencoba OCR on-device untuk mengisi draft. Silakan cek & lengkapi manual.'
                  : 'Barcode kebaca, tapi format BCBP tidak valid. Silakan lengkapi field manual dari hasil yang ada.',
        );
        return;
      }

      final name = (parsed.name ?? parsed.passengerName ?? '').trim();
      final pnr = (parsed.pnr ?? '').trim();
      final origin = (parsed.origin ?? parsed.originAirport ?? '').trim();
      final destination =
          (parsed.destination ?? parsed.destinationAirport ?? '').trim();
      final flight = (parsed.flightNumber ?? parsed.airlineCode ?? '').trim();
      final date = (parsed.flightDate ?? '').trim();
      final seat = (parsed.seatNumber ?? '').trim();
      final type = (parsed.type ?? 'Adult').trim();
      final category =
          record.source == ManualCaptureScanSource.transit ? 'Transit' : 'Normal';
      final scanPoint =
          record.scanPoint.trim().isEmpty ? 'N/A' : record.scanPoint.trim();

      final draft = ManualEntryParsedDraft(
        barcodeValue: pnr.isEmpty ? raw : pnr,
        passengerName: name.isEmpty ? 'N/A' : name,
        boardingDate: date.isEmpty ? 'N/A' : date,
        seat: seat.isEmpty ? 'N/A' : seat,
        flight: flight.isEmpty ? 'N/A' : flight,
        origin: origin.isEmpty ? 'N/A' : origin,
        destination: destination.isEmpty ? 'N/A' : destination,
        passengerType: type.isEmpty ? 'Adult' : type,
        category: category,
        scanPoint: scanPoint,
        extractionSource: 'barcode',
        extractionConfidence: 0, // computed below
      );
      final draftWithConfidence = ManualEntryParsedDraft(
        barcodeValue: draft.barcodeValue,
        passengerName: draft.passengerName,
        boardingDate: draft.boardingDate,
        seat: draft.seat,
        flight: draft.flight,
        origin: draft.origin,
        destination: draft.destination,
        passengerType: draft.passengerType,
        category: draft.category,
        scanPoint: draft.scanPoint,
        extractionSource: draft.extractionSource,
        extractionConfidence: _essentialConfidence(draft),
      );

      loading.value = const _AiLoadingState(
        step: 'Menyimpan hasil…',
        progress: 0.94,
      );
      final successAll = _hasAllEssentialFilled(draftWithConfidence);
      // HIJAU -> aiGenerated, KUNING -> pending
      final updated = record.copyWith(
        parsed: draftWithConfidence,
        status: successAll
            ? ManualEntryCaptureWorkflowStatus.aiGenerated
            : ManualEntryCaptureWorkflowStatus.pending,
      );
      await ManualEntryCaptureStore.instance.updateById(record.id, updated);

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await _showAiGeneratedResultDialog(
        updated,
        title: successAll
            ? 'Hasil Generate Otomatis (Tersimpan)'
            : 'Hasil Generate Otomatis (Draft)',
        subtitle: successAll
            ? 'Data sudah tersimpan di tab Auto Generated. Silakan cek ulang, lalu Publish jika sudah benar.'
            : 'Sebagian field berhasil diisi otomatis dan tersimpan sebagai draft. Silakan lengkapi manual lewat Edit.',
      );
    } catch (e, st) {
      debugPrint('Generate Otomatis (barcode/OCR) failed: $e\n$st');
      try {
        loading.value = const _AiLoadingState(
          step: 'Menyimpan hasil fallback…',
          progress: 0.94,
        );
        final draft = fallbackDraft();
        // Fallback -> tetap pending (merah/kuning ditentukan dari konten draft).
        final updated = record.copyWith(
          parsed: draft,
          status: ManualEntryCaptureWorkflowStatus.pending,
        );
        await ManualEntryCaptureStore.instance.updateById(record.id, updated);
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        await _showAiGeneratedResultDialog(
          updated,
          title: 'Hasil Generate (Fallback)',
          subtitle:
              'Terjadi error saat decoding, jadi sistem membuat draft minimal agar kamu tetap bisa melengkapi manual.',
        );
        return;
      } catch (_) {}
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _showSnack('Generate Otomatis gagal diproses. Coba ulang sebentar lagi.');
    }
  }

  // ── Open dialogs ──────────────────────────────────────────────────────────

  Future<void> _openAddNewDataDialog() async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => _AddNewDataDialog(
        session: SessionContextStore.instance,
        fmtDate: _fmtDate,
      ),
    );
  }

  Future<void> _openAddFlightScheduleDialog() async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => const _AddFlightScheduleDialog(),
    );
  }

  Future<void> _openEditEntryDialog(ManualEntryCaptureRecord record) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => _EditManualEntryDialog(
        record: record,
        session: SessionContextStore.instance,
        fmtDate: _fmtDate,
        onPublished: (updatedDraft) async {
          final parsed = updatedDraft.parsed;
          if (parsed == null) return;
          final sessionAirport = SessionContextStore.instance.originCode.trim();
          final draftAirport = updatedDraft.airportCode.trim();
          if (sessionAirport.isNotEmpty &&
              draftAirport.isNotEmpty &&
              sessionAirport != draftAirport) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Tidak bisa publish. Draft ini dibuat untuk bandara $draftAirport, Anda sedang login di $sessionAirport.'),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }
          PassengerScanStore.instance.addFromManualEntry(
            passengerName: parsed.passengerName,
            boardingDate: parsed.boardingDate,
            seat: parsed.seat,
            flight: parsed.flight,
            origin: parsed.origin,
            destination: parsed.destination,
            passengerType: parsed.passengerType,
            category: parsed.category,
            barcodeValue: parsed.barcodeValue,
            airportCode: draftAirport,
            scanPoint: parsed.scanPoint,
            scannedAt: updatedDraft.createdAt,
          );

          if (mounted &&
              PassengerScanStore.instance.consumeDedupedWarning()) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Data sudah di-scan.'),
                backgroundColor: Colors.orange,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          await ManualEntryCaptureStore.instance.updateById(
            record.id,
            updatedDraft.copyWith(status: ManualEntryCaptureWorkflowStatus.completed),
          );
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1117) : AppTheme.shellScaffoldLight;
    final captures = _filteredCaptures;

    final bottomPad = widget.asShellBody
        ? 18.0 + PionaFloatingNavBar.reserveBottomPadding(context)
        : 18.0;

    final body = SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Action Buttons ──────────────────────────────────────────
            Wrap(
              alignment: WrapAlignment.start,
              spacing: 10,
              runSpacing: 10,
              children: [
                _PillButton(
                  label: 'Add New Data',
                  icon: Icons.add_rounded,
                  onPressed: _openAddNewDataDialog,
                  isDark: isDark,
                ),
                _PillButton(
                  label: 'Add Flight Schedule',
                  icon: Icons.flight_takeoff_rounded,
                  onPressed: _openAddFlightScheduleDialog,
                  isDark: isDark,
                  outlined: true,
                ),
              ],
            ),
            const SizedBox(height: 22),

            // ── Photo Filter ────────────────────────────────────────────
            _SectionHeader(
              title: 'Photos',
              subtitle: 'Filter berdasarkan sumber scan',
              icon: Icons.photo_library_outlined,
              isDark: isDark,
            ),
            const SizedBox(height: 10),
            _FilterChipGroup<ManualEntryPhotoFilter>(
              value: _photoFilter,
              onChanged: (v) => setState(() => _photoFilter = v),
              items: const [
                _FilterItem(
                  value: ManualEntryPhotoFilter.allPhotos,
                  label: 'All Photos',
                  icon: Icons.photo_library_outlined,
                ),
                _FilterItem(
                  value: ManualEntryPhotoFilter.scanNormalPhotos,
                  label: 'Scan Normal',
                  icon: Icons.flight_rounded,
                ),
                _FilterItem(
                  value: ManualEntryPhotoFilter.scanTransitPhotos,
                  label: 'Scan Transit',
                  icon: Icons.transfer_within_a_station_rounded,
                  accentColor: Color(0xFF7C3AED),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // ── Status Filter ───────────────────────────────────────────
            _SectionHeader(
              title: 'Status',
              subtitle: 'Kelola pekerjaan manual entry',
              icon: Icons.filter_alt_outlined,
              isDark: isDark,
            ),
            const SizedBox(height: 10),
            _FilterChipGroup<ManualEntryStatusFilter>(
              value: _statusFilter,
              onChanged: (v) => setState(() => _statusFilter = v),
              items: const [
                _FilterItem(
                  value: ManualEntryStatusFilter.pendingEdit,
                  label: 'Pending',
                  icon: Icons.pending_actions_rounded,
                  accentColor: Color(0xFFF59E0B),
                ),
                _FilterItem(
                  value: ManualEntryStatusFilter.aiGenerated,
                  label: 'Auto Generated',
                  icon: Icons.auto_awesome_rounded,
                  accentColor: Color(0xFF6366F1),
                ),
                _FilterItem(
                  value: ManualEntryStatusFilter.completed,
                  label: 'Completed',
                  icon: Icons.check_circle_rounded,
                  accentColor: Color(0xFF10B981),
                ),
                _FilterItem(
                  value: ManualEntryStatusFilter.trashDeleted,
                  label: 'Trash',
                  icon: Icons.delete_outline_rounded,
                  accentColor: Color(0xFF64748B),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // ── Toolbar ─────────────────────────────────────────────────
            _buildToolbar(isDark, context),
            const SizedBox(height: 12),

            // ── Summary Bar ─────────────────────────────────────────────
            _buildSummaryBar(isDark, context, captures.length),
            const SizedBox(height: 14),

            // ── Content ─────────────────────────────────────────────────
            if (captures.isEmpty)
              _EmptyState(isDark: isDark)
            else
              ...captures.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CaptureCard(
                    record: r,
                    isDark: isDark,
                    formatFileSize: _formatFileSize,
                    formatDateTime: _fmtDateTimeDetail,
                    onDelete: () => _confirmDelete(r),
                    onGenerateAi: () => _runAiGenerated(r),
                    onEdit: () => _openEditEntryDialog(r),
                  ),
                ),
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (widget.asShellBody) return body;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context)
            ? const BackButton(color: Colors.white)
            : null,
        title: const Text('Manual Entry'),
        backgroundColor:
            isDark ? AppTheme.primaryBlueDark : AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: body,
    );
  }

  Widget _buildToolbar(bool isDark, BuildContext context) {
    final borderClr =
        AppTheme.borderColor(context).withValues(alpha: isDark ? 0.65 : 0.7);
    final surfaceClr = isDark ? const Color(0xFF0F172A) : Colors.white;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.bolt_rounded, size: 16),
            label: const Text('Generate All Pending',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              side: BorderSide(color: borderClr),
              foregroundColor: AppTheme.textPrimaryColor(context),
              backgroundColor: surfaceClr,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: surfaceClr,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderClr),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_month_rounded,
                    size: 16, color: AppTheme.primaryBlue),
                const SizedBox(width: 6),
                Text(
                  _fmtDate(_selectedDate),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: AppTheme.textPrimaryColor(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () => setState(() => _selectedDate = DateTime.now()),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: const Text('Today',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildSummaryBar(bool isDark, BuildContext context, int count) {
    final secondary =
        AppTheme.textSecondaryColor(context).withValues(alpha: 0.8);
    final pillBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : AppTheme.primaryBlue.withValues(alpha: 0.08);
    final pillFg = isDark ? Colors.white70 : AppTheme.primaryBlue;
    final dateStr =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

    return Row(
      children: [
        Expanded(
          child: Text(
            '$count foto  ·  Hal. 1/1  ·  $_summaryLabel',
            style: TextStyle(
              fontSize: 11.5,
              color: secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppTheme.borderColor(context)
                  .withValues(alpha: isDark ? 0.4 : 0.5),
            ),
          ),
          child: Text(
            dateStr,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: pillFg,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add New Data Dialog  ← self-contained StatefulWidget (fixes the bug)
// ─────────────────────────────────────────────────────────────────────────────

class _AddNewDataDialog extends StatefulWidget {
  const _AddNewDataDialog({
    required this.session,
    required this.fmtDate,
  });

  final SessionContextStore session;
  final String Function(DateTime) fmtDate;

  @override
  State<_AddNewDataDialog> createState() => _AddNewDataDialogState();
}

class _AddNewDataDialogState extends State<_AddNewDataDialog> {
  final _pnrCtrl = TextEditingController();
  final _passengerCtrl = TextEditingController();
  final _flightCtrl = TextEditingController();
  final _seatCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _pnrFocus = FocusNode();

  DateTime _flightDate = DateTime.now();
  String _type = 'Adult';
  String _category = 'Normal';
  bool _showPnrWarn = false;

  @override
  void dispose() {
    _pnrCtrl.dispose();
    _passengerCtrl.dispose();
    _flightCtrl.dispose();
    _seatCtrl.dispose();
    _destCtrl.dispose();
    _pnrFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showPionaDatePicker(
      context: context,
      initialDate: _flightDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _flightDate = picked);
  }

  void _onSave() {
    if (_pnrCtrl.text.trim().isEmpty) {
      setState(() => _showPnrWarn = true);
      _pnrFocus.requestFocus();
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return _DialogShell(
      title: 'Manual Entry — Add New Data',
      maxHeight: maxH,
      isDark: isDark,
      onClose: () => Navigator.of(context).pop(),
      onCancel: () => Navigator.of(context).pop(),
      onConfirm: _onSave,
      confirmLabel: 'Save Data',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row2(children: [
            _FormField(
              label: 'Flight Date',
              required: true,
              child: _DateTile(
                  text: widget.fmtDate(_flightDate), onTap: _pickDate),
            ),
            _FormField(
              label: 'PNR',
              required: true,
              warning: _showPnrWarn ? 'Please fill out this field.' : null,
              child: TextField(
                controller: _pnrCtrl,
                focusNode: _pnrFocus,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) {
                  if (_showPnrWarn) setState(() => _showPnrWarn = false);
                },
                decoration: _fd(context, hint: 'ENTER PNR'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _FormField(
            label: 'Passenger Name',
            required: true,
            child: TextField(
              controller: _passengerCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: _fd(context, hint: 'ENTER PASSENGER NAME'),
            ),
          ),
          const SizedBox(height: 16),
          _Row2(children: [
            _FormField(
              label: 'Flight Number',
              required: true,
              child: TextField(
                controller: _flightCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _fd(context, hint: 'E.G. GA-234 OR JT-529'),
              ),
            ),
            _FormField(
              label: 'Seat Number',
              required: true,
              child: TextField(
                controller: _seatCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _fd(context, hint: 'E.G., 12A'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _Row2(children: [
            _FormField(
              label: 'Origin',
              child: _ReadonlyTile(
                  text: widget.session.originCode, isDark: isDark),
            ),
            _FormField(
              label: 'Destination',
              required: true,
              child: TextField(
                controller: _destCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration:
                    _fd(context, hint: 'Auto-filled from flight number'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _Row2(children: [
            _FormField(
              label: 'Type',
              child: _DropdownField(
                value: _type,
                items: const ['Adult', 'Infant'],
                onChanged: (v) => setState(() => _type = v!),
              ),
            ),
            _FormField(
              label: 'Category',
              child: _DropdownField(
                value: _category,
                items: const ['Normal', 'Transit'],
                onChanged: (v) => setState(() => _category = v!),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _FormField(
            label: 'Scan Point',
            child: _ReadonlyTile(
                text: widget.session.scanPoint, isDark: isDark),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Flight Schedule Dialog  ← self-contained StatefulWidget (fixes the bug)
// ─────────────────────────────────────────────────────────────────────────────

class _AddFlightScheduleDialog extends StatefulWidget {
  const _AddFlightScheduleDialog();

  @override
  State<_AddFlightScheduleDialog> createState() =>
      _AddFlightScheduleDialogState();
}

class _AddFlightScheduleDialogState extends State<_AddFlightScheduleDialog> {
  final _flightCtrl = TextEditingController();
  final _gateCtrl = TextEditingController();
  final _stationCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _flightFocus = FocusNode();

  DateTime? _scheduledDt;
  TimeOfDay? _boardingTime;
  String? _arrDep;
  bool _showFlightWarn = false;

  @override
  void dispose() {
    _flightCtrl.dispose();
    _gateCtrl.dispose();
    _stationCtrl.dispose();
    _descCtrl.dispose();
    _flightFocus.dispose();
    super.dispose();
  }

  Future<void> _pickScheduled() async {
    final result = await showDialog<dynamic>(
      context: context,
      useRootNavigator: true,
      builder: (_) =>
          _ScheduledDateTimePickerDialog(initialDateTime: _scheduledDt),
    );
    if (!mounted) return;
    if (result == _kFlightSchedulePickerClear) {
      setState(() => _scheduledDt = null);
    } else if (result is DateTime) {
      setState(() => _scheduledDt = result);
    }
  }

  Future<void> _pickBoarding() async {
    final result = await showDialog<TimeOfDay>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _BoardingTimeWheelDialog(initial: _boardingTime),
    );
    if (result != null && mounted) setState(() => _boardingTime = result);
  }

  void _onSave() {
    if (_flightCtrl.text.trim().isEmpty) {
      setState(() => _showFlightWarn = true);
      _flightFocus.requestFocus();
      return;
    }
    Navigator.of(context).pop();
  }

  String get _scheduledDisplay {
    if (_scheduledDt == null) return 'dd/mm/yyyy --:--';
    final dt = _scheduledDt!;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String get _boardingDisplay {
    if (_boardingTime == null) return '-- : --';
    return '${_boardingTime!.hour.toString().padLeft(2, '0')}:${_boardingTime!.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return _DialogShell(
      title: 'Add Flight Schedule',
      maxHeight: maxH,
      isDark: isDark,
      onClose: () => Navigator.of(context).pop(),
      onCancel: () => Navigator.of(context).pop(),
      onConfirm: _onSave,
      confirmLabel: 'Save Flight Schedule',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row2(children: [
            _FormField(
              label: 'Flight Number',
              required: true,
              warning: _showFlightWarn ? 'Please fill out this field.' : null,
              child: TextField(
                controller: _flightCtrl,
                focusNode: _flightFocus,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) {
                  if (_showFlightWarn)
                    setState(() => _showFlightWarn = false);
                },
                decoration: _fd(context, hint: 'E.G. GA-234 OR JT-529'),
              ),
            ),
            _FormField(
              label: 'Scheduled Date/Time',
              required: true,
              child: _DateTile(
                text: _scheduledDisplay,
                placeholder: _scheduledDt == null,
                onTap: _pickScheduled,
                icon: Icons.calendar_today_outlined,
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _Row2(children: [
            _FormField(
              label: 'Gate Code',
              child: TextField(
                controller: _gateCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _fd(context, hint: 'E.G. A1, B2'),
              ),
            ),
            _FormField(
              label: 'Boarding Time',
              child: _DateTile(
                text: _boardingDisplay,
                placeholder: _boardingTime == null,
                onTap: _pickBoarding,
                icon: Icons.access_time_rounded,
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _Row2(children: [
            _FormField(
              label: 'Station / Origin',
              child: TextField(
                controller: _stationCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _fd(context, hint: 'E.G. CGK, DPS'),
              ),
            ),
            _FormField(
              label: 'Arr / Dep',
              child: _DropdownField(
                value: _arrDep,
                items: const ['Arrival', 'Departure'],
                hint: 'Select...',
                onChanged: (v) => setState(() => _arrDep = v),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _FormField(
            label: 'Description',
            child: TextField(
              controller: _descCtrl,
              maxLines: 3,
              minLines: 2,
              decoration: _fd(context, hint: 'Flight description'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Manual Entry Dialog (save draft, publish when complete)
// ─────────────────────────────────────────────────────────────────────────────

class _EditManualEntryDialog extends StatefulWidget {
  const _EditManualEntryDialog({
    required this.record,
    required this.session,
    required this.fmtDate,
    required this.onPublished,
  });

  final ManualEntryCaptureRecord record;
  final SessionContextStore session;
  final String Function(DateTime) fmtDate;
  final Future<void> Function(ManualEntryCaptureRecord updatedDraft) onPublished;

  @override
  State<_EditManualEntryDialog> createState() => _EditManualEntryDialogState();
}

class _EditManualEntryDialogState extends State<_EditManualEntryDialog> {
  final _pnrCtrl = TextEditingController();
  final _passengerCtrl = TextEditingController();
  final _flightCtrl = TextEditingController();
  final _seatCtrl = TextEditingController();
  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _scanPointCtrl = TextEditingController();
  final _pnrFocus = FocusNode();

  DateTime _flightDate = DateTime.now();
  String _type = 'Adult';
  String _category = 'Normal';
  bool _showWarn = false;

  @override
  void initState() {
    super.initState();
    final parsed = widget.record.parsed;
    if (parsed != null) {
      _pnrCtrl.text = parsed.barcodeValue;
      _passengerCtrl.text = parsed.passengerName;
      _flightCtrl.text = parsed.flight;
      _seatCtrl.text = parsed.seat;
      _originCtrl.text = parsed.origin;
      _destCtrl.text = parsed.destination;
      _type = parsed.passengerType.trim().isEmpty ? _type : parsed.passengerType;
      _category =
          parsed.category.trim().isEmpty ? _category : parsed.category;
      _scanPointCtrl.text = parsed.scanPoint;
      _flightDate = _tryParseDate(parsed.boardingDate) ?? _flightDate;
    } else {
      _originCtrl.text = widget.session.originCode;
      _scanPointCtrl.text = widget.session.scanPoint;
    }
  }

  DateTime? _tryParseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty || s == 'N/A' || s == '—') return null;
    // Expected `YYYY-MM-DD` used elsewhere.
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _pnrCtrl.dispose();
    _passengerCtrl.dispose();
    _flightCtrl.dispose();
    _seatCtrl.dispose();
    _originCtrl.dispose();
    _destCtrl.dispose();
    _scanPointCtrl.dispose();
    _pnrFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showPionaDatePicker(
      context: context,
      initialDate: _flightDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _flightDate = picked);
  }

  bool _isEmpty(String s) {
    final v = s.trim();
    return v.isEmpty || v == 'N/A' || v == '—';
  }

  Future<void> _onSaveDraft() async {
    final draft = ManualEntryParsedDraft(
      barcodeValue: _pnrCtrl.text.trim(),
      passengerName: _passengerCtrl.text.trim(),
      boardingDate: widget.fmtDate(_flightDate),
      seat: _seatCtrl.text.trim(),
      flight: _flightCtrl.text.trim(),
      origin: _originCtrl.text.trim(),
      destination: _destCtrl.text.trim(),
      passengerType: _type,
      category: _category,
      scanPoint: _scanPointCtrl.text.trim(),
    );

    await ManualEntryCaptureStore.instance.updateById(
      widget.record.id,
      widget.record.copyWith(
        parsed: draft,
        status: widget.record.status == ManualEntryCaptureWorkflowStatus.aiGenerated
            ? ManualEntryCaptureWorkflowStatus.aiGenerated
            : ManualEntryCaptureWorkflowStatus.pending,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _onPublish() async {
    final required = <String, String>{
      'PNR/Barcode': _pnrCtrl.text,
      'Passenger Name': _passengerCtrl.text,
      'Flight Number': _flightCtrl.text,
      'Seat Number': _seatCtrl.text,
      'Origin': _originCtrl.text,
      'Destination': _destCtrl.text,
      'Scan Point': _scanPointCtrl.text,
      'Type': _type,
      'Category': _category,
      'Flight Date': widget.fmtDate(_flightDate),
    };
    final missing = required.entries.where((e) => _isEmpty(e.value)).toList();
    if (missing.isNotEmpty) {
      setState(() => _showWarn = true);
      _pnrFocus.requestFocus();
      return;
    }

    final draft = ManualEntryParsedDraft(
      barcodeValue: _pnrCtrl.text.trim(),
      passengerName: _passengerCtrl.text.trim(),
      boardingDate: widget.fmtDate(_flightDate),
      seat: _seatCtrl.text.trim(),
      flight: _flightCtrl.text.trim(),
      origin: _originCtrl.text.trim(),
      destination: _destCtrl.text.trim(),
      passengerType: _type,
      category: _category,
      scanPoint: _scanPointCtrl.text.trim(),
    );

    final updated = widget.record.copyWith(
      parsed: draft,
      status: ManualEntryCaptureWorkflowStatus.completed,
    );

    await widget.onPublished(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return _DialogShell(
      title: 'Manual Entry — Edit & Save',
      maxHeight: maxH,
      isDark: isDark,
      onClose: () => Navigator.of(context).pop(),
      onCancel: () => Navigator.of(context).pop(),
      secondaryLabel: 'Save',
      onSecondary: _onSaveDraft,
      onConfirm: _onPublish,
      confirmLabel: 'Publish',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showWarn)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _WarnBanner(
                text:
                    'Semua field wajib diisi sebelum data bisa masuk ke Passenger List/Dashboard.',
                isDark: isDark,
              ),
            ),
          _Row2(children: [
            _FormField(
              label: 'Flight Date',
              required: true,
              child: _DateTile(text: widget.fmtDate(_flightDate), onTap: _pickDate),
            ),
            _FormField(
              label: 'PNR/Barcode',
              required: true,
              child: TextField(
                controller: _pnrCtrl,
                focusNode: _pnrFocus,
                textCapitalization: TextCapitalization.characters,
                decoration: _fd(context, hint: 'ENTER PNR / BARCODE'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _FormField(
            label: 'Passenger Name',
            required: true,
            child: TextField(
              controller: _passengerCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: _fd(context, hint: 'ENTER PASSENGER NAME'),
            ),
          ),
          const SizedBox(height: 16),
          _Row2(children: [
            _FormField(
              label: 'Flight Number',
              required: true,
              child: TextField(
                controller: _flightCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _fd(context, hint: 'E.G. GA-234 OR JT-529'),
              ),
            ),
            _FormField(
              label: 'Seat Number',
              required: true,
              child: TextField(
                controller: _seatCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _fd(context, hint: 'E.G., 12A'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _Row2(children: [
            _FormField(
              label: 'Origin',
              required: true,
              child: TextField(
                controller: _originCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _fd(context, hint: 'E.G. CGK'),
              ),
            ),
            _FormField(
              label: 'Destination',
              required: true,
              child: TextField(
                controller: _destCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _fd(context, hint: 'E.G. DPS'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _Row2(children: [
            _FormField(
              label: 'Type',
              required: true,
              child: _DropdownField(
                value: _type,
                items: const ['Adult', 'Infant'],
                onChanged: (v) => setState(() => _type = v!),
              ),
            ),
            _FormField(
              label: 'Category',
              required: true,
              child: _DropdownField(
                value: _category,
                items: const ['Normal', 'Transit'],
                onChanged: (v) => setState(() => _category = v!),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _FormField(
            label: 'Scan Point',
            required: true,
            child: TextField(
              controller: _scanPointCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: _fd(context, hint: 'E.G. Gate A1 / Bandara'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarnBanner extends StatelessWidget {
  const _WarnBanner({required this.text, required this.isDark});
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF2A1518) : const Color(0xFFFFF7F7);
    final border = isDark ? const Color(0xFF7F2D2D) : const Color(0xFFE53935);
    final fg = isDark ? const Color(0xFFFFCDD2) : const Color(0xFFB71C1C);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withValues(alpha: 0.8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: fg, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog Shell  (layout only — no close/save callbacks that need outer context)
// ─────────────────────────────────────────────────────────────────────────────

class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.title,
    required this.child,
    required this.onClose,
    required this.onCancel,
    this.onSecondary,
    this.secondaryLabel,
    required this.onConfirm,
    required this.confirmLabel,
    required this.maxHeight,
    required this.isDark,
  });

  final String title;
  final Widget child;
  final VoidCallback onClose;
  final VoidCallback onCancel;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final double maxHeight;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.borderColor(context).withValues(alpha: 0.65),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.14),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 10, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimaryColor(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                    visualDensity: VisualDensity.compact,
                    color: AppTheme.textSecondaryColor(context),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: AppTheme.borderColor(context).withValues(alpha: 0.45),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: child,
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: AppTheme.borderColor(context).withValues(alpha: 0.45),
            ),
            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimaryColor(context),
                      side: BorderSide(color: AppTheme.borderColor(context)),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 11),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  if (onSecondary != null && secondaryLabel != null) ...[
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: onSecondary,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryBlue,
                        side: const BorderSide(color: AppTheme.primaryBlue),
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 11),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        secondaryLabel!,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 11),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(confirmLabel,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Shared InputDecoration factory.
InputDecoration _fd(BuildContext ctx, {required String hint, bool readOnly = false}) {
  final isDark = Theme.of(ctx).brightness == Brightness.dark;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: AppTheme.borderColor(ctx)),
  );
  return InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: readOnly
        ? (isDark
            ? AppTheme.darkSurfaceElevated.withValues(alpha: 0.5)
            : const Color(0xFFF0F2F5))
        : (isDark
            ? AppTheme.darkSurfaceElevated.withValues(alpha: 0.65)
            : Colors.white),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
    ),
    hintStyle: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: AppTheme.textSecondaryColor(ctx).withValues(alpha: 0.55),
    ),
  );
}

/// Responsive 2-column row.
class _Row2 extends StatelessWidget {
  const _Row2({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      if (c.maxWidth < 400) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              children[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(child: children[i]),
          ],
        ],
      );
    });
  }
}

/// Label + child + optional warning.
class _FormField extends StatelessWidget {
  const _FormField({
    required this.label,
    required this.child,
    this.required = false,
    this.warning,
  });

  final String label;
  final Widget child;
  final bool required;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondaryColor(context),
              letterSpacing: 0.1,
            ),
            children: [
              TextSpan(text: label),
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(
                      color: Color(0xFFE53935), fontWeight: FontWeight.w800),
                ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        child,
        if (warning != null) ...[
          const SizedBox(height: 6),
          _WarnTooltip(message: warning!),
        ],
      ],
    );
  }
}

class _WarnTooltip extends StatelessWidget {
  const _WarnTooltip({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    height: 1)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF78350F))),
          ),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.text,
    required this.onTap,
    this.placeholder = false,
    this.icon = Icons.calendar_today_outlined,
  });

  final String text;
  final VoidCallback onTap;
  final bool placeholder;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: _fd(context, hint: '').copyWith(
          suffixIcon: Icon(icon, size: 17, color: AppTheme.textSecondary),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: placeholder
                ? AppTheme.textSecondaryColor(context).withValues(alpha: 0.55)
                : AppTheme.textPrimaryColor(context),
          ),
        ),
      ),
    );
  }
}

class _ReadonlyTile extends StatelessWidget {
  const _ReadonlyTile({required this.text, required this.isDark});
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: _fd(context, hint: '', readOnly: true),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimaryColor(context),
        ),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: _fd(context, hint: ''),
      hint: hint != null
          ? Text(hint!,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.textSecondaryColor(context)
                      .withValues(alpha: 0.55)))
          : null,
      items: items
          .map((s) => DropdownMenuItem(
              value: s,
              child: Text(s,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600))))
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.isDark,
    this.outlined = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isDark;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryBlue,
          side: BorderSide(
              color: AppTheme.primaryBlue.withValues(alpha: 0.55)),
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: isDark ? 0 : 1,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isDark,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: isDark ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primaryBlue, size: 17),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimaryColor(context),
                    letterSpacing: -0.1,
                  )),
              Text(subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondaryColor(context)
                        .withValues(alpha: 0.8),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterItem<T> {
  const _FilterItem({
    required this.value,
    required this.label,
    required this.icon,
    this.accentColor = AppTheme.primaryBlue,
  });

  final T value;
  final String label;
  final IconData icon;
  final Color accentColor;
}

class _FilterChipGroup<T> extends StatelessWidget {
  const _FilterChipGroup({
    required this.value,
    required this.onChanged,
    required this.items,
  });

  final T value;
  final ValueChanged<T> onChanged;
  final List<_FilterItem<T>> items;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map((item) => _Chip(
                label: item.label,
                icon: item.icon,
                selected: item.value == value,
                isDark: isDark,
                accentColor: item.accentColor,
                onTap: () => onChanged(item.value),
              ))
          .toList(),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isDark,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool isDark;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? accentColor
        : (isDark ? const Color(0xFF0F172A) : Colors.white);
    final fg = selected ? Colors.white : AppTheme.textPrimaryColor(context);
    final outline = selected
        ? accentColor
        : AppTheme.borderColor(context).withValues(alpha: 0.7);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: outline),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: isDark ? 0.3 : 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15, color: selected ? Colors.white : accentColor),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF141C2E) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppTheme.borderColor(context).withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.inbox_rounded,
                color: AppTheme.primaryBlue.withValues(alpha: 0.45), size: 26),
          ),
          const SizedBox(height: 14),
          Text('Tidak ada entri',
              style: TextStyle(
                color: AppTheme.textPrimaryColor(context),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              )),
          const SizedBox(height: 6),
          Text(
            'Tidak ada data untuk tanggal dan filter ini.\n'
            'Gunakan Manual Capture di halaman Scan jika barcode gagal dipindai.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondaryColor(context),
              fontSize: 12.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Capture Card
// ─────────────────────────────────────────────────────────────────────────────

class _CaptureCard extends StatelessWidget {
  const _CaptureCard({
    required this.record,
    required this.isDark,
    required this.formatFileSize,
    required this.formatDateTime,
    required this.onDelete,
    required this.onGenerateAi,
    required this.onEdit,
  });

  final ManualEntryCaptureRecord record;
  final bool isDark;
  final String Function(int) formatFileSize;
  final String Function(DateTime) formatDateTime;
  final VoidCallback onDelete;
  final VoidCallback onGenerateAi;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final pending = record.status == ManualEntryCaptureWorkflowStatus.pending;
    final surface = isDark ? const Color(0xFF141C2E) : Colors.white;
    final border = AppTheme.borderColor(context);

    final cardBg = pending
        ? (isDark ? const Color(0xFF2A1518) : const Color(0xFFFFF7F7))
        : surface;
    final cardBorderColor = pending
        ? (isDark ? const Color(0xFF7F2D2D) : const Color(0xFFE53935))
        : border.withValues(alpha: 0.65);

    final isTransit = record.source == ManualCaptureScanSource.transit;
    final sourceLabel = isTransit ? 'Scan Transit' : 'Scan Normal';
    final sourceColor =
        isTransit ? const Color(0xFF7C3AED) : AppTheme.primaryBlue;

    return FutureBuilder<String>(
      future: ManualEntryCaptureStore.instance.fileAbsolutePath(record),
      builder: (context, snap) {
        final path = snap.data;
        final fileOk = path != null && File(path).existsSync();

        return Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: cardBorderColor, width: pending ? 1.5 : 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                child: Row(
                  children: [
                    _Badge(label: sourceLabel, color: sourceColor, isDark: isDark),
                    const SizedBox(width: 8),
                    if (pending)
                      _Badge(
                          label: 'Pending Entry',
                          color: const Color(0xFFE53935),
                          isDark: isDark),
                    const Spacer(),
                    Text('ID: ${record.id}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondaryColor(context)
                              .withValues(alpha: 0.6),
                        )),
                  ],
                ),
              ),
              Divider(
                  height: 1,
                  thickness: 1,
                  color: cardBorderColor.withValues(alpha: 0.35)),

              // Body
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: fileOk
                            ? Image.file(File(path),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _ImgPlaceholder(isDark: isDark, error: true))
                            : _ImgPlaceholder(isDark: isDark),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _InfoSection(title: 'File Information', rows: [
                            _InfoRow('Filename', record.displayFileName),
                            _InfoRow('Size', formatFileSize(record.sizeBytes)),
                            _InfoRow('Created', formatDateTime(record.createdAt)),
                          ]),
                          const SizedBox(height: 12),
                          _InfoSection(title: 'Session', rows: [
                            _InfoRow('User', record.userDisplay),
                            _InfoRow('Scan Point',
                                record.scanPoint.isEmpty ? '—' : record.scanPoint),
                            _InfoRow('Airport',
                                record.airportCode.isEmpty ? '—' : record.airportCode),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _CardAction(
                      label: 'Generate Otomatis',
                      icon: Icons.bolt_rounded,
                      color: const Color(0xFF6366F1),
                      onPressed: onGenerateAi,
                    ),
                    const SizedBox(width: 8),
                    _CardAction(
                      label: 'Edit',
                      icon: Icons.edit_outlined,
                      color: AppTheme.primaryBlue,
                      onPressed: onEdit,
                    ),
                    const SizedBox(width: 8),
                    _CardAction(
                      label: 'Delete',
                      icon: Icons.delete_outline_rounded,
                      color: const Color(0xFFE53935),
                      onPressed: onDelete,
                      filled: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.rows});
  final String title;
  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color:
                  AppTheme.textSecondaryColor(context).withValues(alpha: 0.7),
              letterSpacing: 0.4,
            )),
        const SizedBox(height: 5),
        ...rows,
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondaryColor(context)
                      .withValues(alpha: 0.75),
                )),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimaryColor(context),
                  height: 1.3,
                )),
          ),
        ],
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    const pad = EdgeInsets.symmetric(horizontal: 10, vertical: 7);
    const lblStyle = TextStyle(fontWeight: FontWeight.w700, fontSize: 12);
    const minSz = Size(0, 34);
    const tapTarget = MaterialTapTargetSize.shrinkWrap;

    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: const Text('Delete', style: lblStyle),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: pad,
          minimumSize: minSz,
          tapTargetSize: tapTarget,
          shape: shape,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label, style: lblStyle),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: pad,
        minimumSize: minSz,
        tapTargetSize: tapTarget,
        shape: shape,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, required this.isDark});
  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
            color: isDark ? color.withValues(alpha: 0.9) : color,
            fontWeight: FontWeight.w800,
            fontSize: 10.5,
          )),
    );
  }
}

class _ImgPlaceholder extends StatelessWidget {
  const _ImgPlaceholder({required this.isDark, this.error = false});
  final bool isDark;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color:
          isDark ? const Color(0xFF1C2333) : const Color(0xFFEFF1F5),
      child: Icon(
        error
            ? Icons.broken_image_outlined
            : Icons.image_not_supported_outlined,
        color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
        size: 28,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scheduled Date/Time Picker
// ─────────────────────────────────────────────────────────────────────────────

class _ScheduledDateTimePickerDialog extends StatefulWidget {
  const _ScheduledDateTimePickerDialog({this.initialDateTime});
  final DateTime? initialDateTime;

  @override
  State<_ScheduledDateTimePickerDialog> createState() =>
      _ScheduledDateTimePickerDialogState();
}

class _ScheduledDateTimePickerDialogState
    extends State<_ScheduledDateTimePickerDialog> {
  late DateTime _day;
  late int _hour;
  late int _minute;
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minuteCtrl;
  int _calKey = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final seed = widget.initialDateTime ?? now;
    _day = DateTime(seed.year, seed.month, seed.day);
    _hour = seed.hour;
    _minute = seed.minute;
    _hourCtrl = FixedExtentScrollController(initialItem: _hour);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  void _applyToday() {
    final n = DateTime.now();
    setState(() {
      _day = DateTime(n.year, n.month, n.day);
      _hour = n.hour;
      _minute = n.minute;
      _calKey++;
      if (_hourCtrl.hasClients) _hourCtrl.jumpToItem(_hour);
      if (_minuteCtrl.hasClients) _minuteCtrl.jumpToItem(_minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final blue = AppTheme.primaryBlue;
    return Theme(
      data: ThemeData.light().copyWith(
        colorScheme: ColorScheme.light(
          primary: blue,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: const Color(0xFF1A1A1A),
        ),
      ),
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 300,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 58,
                        child: PionaCalendarViewport(
                          key: ValueKey<int>(_calKey),
                          selectedDate: _day,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          showFooter: false,
                          onDayCommitted: (d) => setState(
                              () => _day = DateTime(d.year, d.month, d.day)),
                        ),
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(
                        flex: 34,
                        child: _TimeWheelPair(
                          hourController: _hourCtrl,
                          minuteController: _minuteCtrl,
                          onHourChanged: (i) => setState(() => _hour = i),
                          onMinuteChanged: (i) => setState(() => _minute = i),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context)
                            .pop(_kFlightSchedulePickerClear),
                        child: Text('Clear',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: blue)),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _applyToday,
                        child: Text('Today',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: blue)),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(
                        DateTime(_day.year, _day.month, _day.day, _hour, _minute),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('OK',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Time Wheel Pair
// ─────────────────────────────────────────────────────────────────────────────

class _TimeWheelPair extends StatelessWidget {
  const _TimeWheelPair({
    required this.hourController,
    required this.minuteController,
    required this.onHourChanged,
    required this.onMinuteChanged,
  });

  final FixedExtentScrollController hourController;
  final FixedExtentScrollController minuteController;
  final ValueChanged<int> onHourChanged;
  final ValueChanged<int> onMinuteChanged;

  @override
  Widget build(BuildContext context) {
    const itemExtent = 36.0;
    final blue = AppTheme.primaryBlue;

    Widget wheel({
      required int count,
      required FixedExtentScrollController controller,
      required ValueChanged<int> onChanged,
      required String Function(int) fmt,
    }) {
      return Expanded(
        child: Stack(
          alignment: Alignment.center,
          children: [
            ListWheelScrollView.useDelegate(
              controller: controller,
              itemExtent: itemExtent,
              physics: const FixedExtentScrollPhysics(),
              perspective: 0.002,
              diameterRatio: 1.35,
              onSelectedItemChanged: onChanged,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: count,
                builder: (ctx, i) => Center(
                  child: Text(fmt(i),
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary.withValues(alpha: 0.5))),
                ),
              ),
            ),
            IgnorePointer(
              child: Container(
                height: itemExtent + 4,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 1.5),
                  borderRadius: BorderRadius.circular(4),
                  color: blue.withValues(alpha: 0.22),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        wheel(
          count: 24,
          controller: hourController,
          onChanged: onHourChanged,
          fmt: (i) => i.toString().padLeft(2, '0'),
        ),
        wheel(
          count: 60,
          controller: minuteController,
          onChanged: onMinuteChanged,
          fmt: (i) => i.toString().padLeft(2, '0'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Boarding Time Wheel Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _BoardingTimeWheelDialog extends StatefulWidget {
  const _BoardingTimeWheelDialog({this.initial});
  final TimeOfDay? initial;

  @override
  State<_BoardingTimeWheelDialog> createState() =>
      _BoardingTimeWheelDialogState();
}

class _BoardingTimeWheelDialogState extends State<_BoardingTimeWheelDialog> {
  late int _hour;
  late int _minute;
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minuteCtrl;

  @override
  void initState() {
    super.initState();
    final seed = widget.initial ?? const TimeOfDay(hour: 0, minute: 0);
    _hour = seed.hour;
    _minute = seed.minute;
    _hourCtrl = FixedExtentScrollController(initialItem: _hour);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blue = AppTheme.primaryBlue;
    return Theme(
      data: ThemeData.light().copyWith(
        colorScheme: ColorScheme.light(
          primary: blue,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: const Color(0xFF1A1A1A),
        ),
      ),
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Boarding Time',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 14),
                SizedBox(
                  height: 220,
                  child: _TimeWheelPair(
                    hourController: _hourCtrl,
                    minuteController: _minuteCtrl,
                    onHourChanged: (i) => setState(() => _hour = i),
                    onMinuteChanged: (i) => setState(() => _minute = i),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context)
                          .pop(TimeOfDay(hour: _hour, minute: _minute)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('OK',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
