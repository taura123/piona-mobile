import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/manual_entry_capture_store.dart';
import '../services/passenger_scan_store.dart';
import 'manual_entry_screen.dart';
import '../services/session_context_store.dart';
import '../theme/app_theme.dart';
import '../utils/bcbp_parser.dart';
import 'home_screen.dart';
import '../widgets/piona_shell_scaffold.dart';
import '../widgets/result_modal.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums & Data Models
// ─────────────────────────────────────────────────────────────────────────────

enum ScanMode { normal, transit }

typedef ScanSuccessCallback = void Function(
  ScanResultDisplay result,
  ScanMode mode,
);

/// Completeness level of a parsed boarding pass.
enum ParseStatus {
  /// All critical fields present and valid.
  complete,

  /// Parsed successfully but some optional/secondary fields are missing.
  partial,

  /// Could not parse the barcode at all.
  failed,
}

class ScanResultDisplay {
  const ScanResultDisplay({
    required this.passengerName,
    required this.boardingDate,
    required this.seat,
    required this.gate,
    required this.criteria,
    required this.isValid,
    required this.origin,
    required this.destination,
    required this.airlineCode,
    required this.boardingTime,
    required this.schedule,
    required this.scannedAt,
    required this.barcodeValue,
    required this.status,
    this.missingFields = const [],
  });

  final String passengerName;
  final String boardingDate;
  final String seat;
  final String gate;
  final String criteria;
  final bool isValid;
  final String origin;
  final String destination;
  final String airlineCode;
  final String boardingTime;
  final String schedule;
  final DateTime scannedAt;
  final String barcodeValue;

  /// Completeness status — drives the status badge color.
  final ParseStatus status;

  /// List of field names that are missing/N-A (shown in warning).
  final List<String> missingFields;
}

// ─────────────────────────────────────────────────────────────────────────────
// ScanScreen
// ─────────────────────────────────────────────────────────────────────────────

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    this.mode = ScanMode.normal,
    this.onScanSuccess,
    this.scanPointFallback,
  });

  final ScanMode mode;
  final ScanSuccessCallback? onScanSuccess;

  /// Used when persisting to [PassengerScanStore] if gate is empty (e.g. bandara).
  final String? scanPointFallback;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with TickerProviderStateMixin {
  static const String _kDefaultScanPoint = 'Concordia';

  final GlobalKey _cameraPreviewKey = GlobalKey(debugLabel: 'scanCameraPreview');

  // ── Controllers ────────────────────────────────────────────────────────────
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  final TextEditingController _manualCtrl = TextEditingController();

  // ── Animation controllers (nullable — safe against hot-reload) ────────────
  AnimationController? _laserCtrl;
  AnimationController? _pulseCtrl;
  AnimationController? _resultCtrl;
  Animation<double> _resultFade = kAlwaysCompleteAnimation;
  Animation<Offset> _resultSlide = const AlwaysStoppedAnimation(Offset.zero);

  // ── State ──────────────────────────────────────────────────────────────────
  PermissionStatus _cameraPermission = PermissionStatus.denied;
  bool _permissionChecked = false;
  bool _isScanning = true;
  bool _torchOn = false;
  bool _manualCaptureBusy = false;
  ScanResultDisplay? _lastResult;
  VoidCallback? _scanStoreListener;

  static const String _na = 'N/A';

  @override
  void initState() {
    super.initState();

    final laser = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    final pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    final result = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _laserCtrl = laser;
    _pulseCtrl = pulse;
    _resultCtrl = result;

    _resultFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: result, curve: Curves.easeOut),
    );
    _resultSlide =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: result, curve: Curves.easeOutCubic),
    );

    _scanStoreListener = () {
      final did = PassengerScanStore.instance.consumeDedupedWarning();
      if (!did) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Data sudah di-scan.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    };
    PassengerScanStore.instance.addListener(_scanStoreListener!);

    _requestCameraPermission();
  }

  @override
  void dispose() {
    if (_scanStoreListener != null) {
      PassengerScanStore.instance.removeListener(_scanStoreListener!);
    }
    _laserCtrl?.dispose();
    _pulseCtrl?.dispose();
    _resultCtrl?.dispose();
    _manualCtrl.dispose();
    _scanner.dispose();
    super.dispose();
  }

  // ── Permission ─────────────────────────────────────────────────────────────

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      if (!mounted) return;
      setState(() {
        _cameraPermission = PermissionStatus.granted;
        _permissionChecked = true;
      });
      return;
    }
    if (status.isPermanentlyDenied) {
      if (!mounted) return;
      setState(() {
        _cameraPermission = PermissionStatus.permanentlyDenied;
        _permissionChecked = true;
      });
      return;
    }
    final result = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _cameraPermission = result;
      _permissionChecked = true;
    });
  }

  Future<void> _openAppSettings() async {
    await openAppSettings();
    final status = await Permission.camera.status;
    if (!mounted) return;
    setState(() => _cameraPermission = status);
  }

  // ── Parsing ────────────────────────────────────────────────────────────────

  /// Parse raw BCBP, determine completeness, and assign [_lastResult].
  /// Returns the [ParseStatus].
  ParseStatus _applyParsedResult(String rawValue) {
    final now = DateTime.now();

    final parsed = parseBCBP(rawValue);

    if (!parsed.isSuccess) {
      setState(() {
        _lastResult = ScanResultDisplay(
          passengerName: parsed.name ?? '—',
          boardingDate: '—',
          seat: '—',
          gate: '—',
          criteria: '—',
          isValid: false,
          origin: '—',
          destination: '—',
          airlineCode: '—',
          boardingTime: '—',
          schedule: 'Parse error',
          scannedAt: now,
          barcodeValue: rawValue,
          status: ParseStatus.failed,
          missingFields: [],
        );
      });
      _resultCtrl?.forward(from: 0);
      return ParseStatus.failed;
    }

    // Map parsed fields
    final name = parsed.name ?? parsed.passengerName ?? '';
    final date = parsed.flightDate ?? '';
    final seat = parsed.seatNumber ?? '';
    final origin = parsed.origin ?? parsed.originAirport ?? '';
    final destination = parsed.destination ?? parsed.destinationAirport ?? '';
    final airlineRaw = parsed.flightNumber ?? parsed.airlineCode ?? '';
    final airline = RegExp(r'^[A-Z0-9]{2}\d{3,5}$').hasMatch(airlineRaw)
        ? '${airlineRaw.substring(0, 2)} ${airlineRaw.substring(2)}'
        : airlineRaw;
    final boardingTime = parsed.boardingTime ?? '';
    final gate = widget.scanPointFallback ?? _kDefaultScanPoint;
    final criteria = parsed.type ?? 'Adult';
    final schedule =
        (parsed.passengerStatus != null && parsed.passengerStatus != _na)
            ? parsed.passengerStatus!
            : 'Scheduled';

    // Strict mode: ALL fields required for publishing to Passenger List/Dashboard.
    final category = widget.mode == ScanMode.transit ? 'Transit' : 'Normal';
    final Map<String, String> fieldMap = {
      'PNR/Barcode': rawValue,
      'Nama Penumpang': name,
      'Tanggal': date,
      'Seat': seat,
      'Asal': origin,
      'Tujuan': destination,
      'Flight': airline,
      'Type': criteria,
      'Category': category,
      'Scan Point': gate,
    };

    final missing = fieldMap.entries
        .where((e) => e.value.trim().isEmpty || e.value == _na)
        .map((e) => e.key)
        .toList();

    final status = missing.isEmpty ? ParseStatus.complete : ParseStatus.partial;

    ScanResultDisplay? computed;
    setState(() {
      computed = ScanResultDisplay(
        passengerName: name.isEmpty ? _na : name,
        boardingDate: date.isEmpty ? _na : date,
        seat: seat.isEmpty ? _na : seat,
        gate: gate,
        criteria: criteria,
        isValid: status != ParseStatus.failed,
        origin: origin.isEmpty ? _na : origin,
        destination: destination.isEmpty ? _na : destination,
        airlineCode: airline.isEmpty ? _na : airline,
        boardingTime: boardingTime.isEmpty ? _na : boardingTime,
        schedule: schedule,
        scannedAt: now,
        barcodeValue: rawValue,
        status: status,
        missingFields: missing,
      );
      _lastResult = computed;
    });
    final cb = widget.onScanSuccess;
    if (computed != null && status == ParseStatus.complete) {
      PassengerScanStore.instance.addFromScan(
        result: computed!,
        mode: widget.mode,
        scanPointFallback:
            widget.scanPointFallback ?? _kDefaultScanPoint,
      );
      if (cb != null) {
        cb(computed!, widget.mode);
      }
    } else if (computed != null && status == ParseStatus.partial) {
      final session = SessionContextStore.instance;
      ManualEntryCaptureStore.instance.addDraft(
        source: widget.mode == ScanMode.transit
            ? ManualCaptureScanSource.transit
            : ManualCaptureScanSource.normal,
        userDisplay: session.displayUserId,
        scanPoint: session.scanPoint,
        airportCode: session.originCode,
        parsed: ManualEntryParsedDraft(
          barcodeValue: computed!.barcodeValue,
          passengerName: computed!.passengerName,
          boardingDate: computed!.boardingDate,
          seat: computed!.seat,
          flight: computed!.airlineCode,
          origin: computed!.origin,
          destination: computed!.destination,
          passengerType: computed!.criteria,
          category: category,
          scanPoint: gate,
        ),
      );
    }
    _resultCtrl?.forward(from: 0);
    return status;
  }

  // ── Scan actions ───────────────────────────────────────────────────────────

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (!_isScanning) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    setState(() => _isScanning = false);
    _scanner.stop();
    final status = _applyParsedResult(rawValue);
    _showResultModal(rawValue, status);
  }

  void _onManualSubmit() {
    final text = _manualCtrl.text.trim();
    if (text.isEmpty) {
      _showSnack('Masukkan atau tempel raw data BCBP terlebih dahulu.');
      return;
    }
    final status = _applyParsedResult(text);
    _showResultModal(text, status);
  }

  Future<void> _onUploadTxt() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) {
      _showSnack('Tidak dapat membaca file. Pilih file .txt dari perangkat.');
      return;
    }
    final content = utf8.decode(file.bytes!);
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final rawValue = lines.isNotEmpty ? lines.first : content.trim();
    if (rawValue.isEmpty) {
      _showSnack('File kosong atau tidak berisi data BCBP.');
      return;
    }
    if (!mounted) return;
    final status = _applyParsedResult(rawValue);
    _showResultModal(rawValue, status);
  }

  void _showResultModal(String rawValue, ParseStatus status) {
    final parsed = parseBCBP(rawValue);
    showModalBottomSheet<ScanResultSheetAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ResultModal(
        status: status,
        barcodeValue: status != ParseStatus.failed
            ? rawValue
            : '${parsed.rawData}\n\nError: ${parsed.error}',
      ),
    ).then((action) async {
      if (!mounted) return;
      if (action == ScanResultSheetAction.openManualEntry) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const ManualEntryScreen(),
          ),
        );
        if (!mounted) return;
        setState(() => _isScanning = true);
        _scanner.start();
        return;
      }
      setState(() => _isScanning = true);
      _scanner.start();
    });
  }

  void _onReset() {
    setState(() {
      _lastResult = null;
      _isScanning = true;
    });
    _scanner.start();
    _showSnack('Scanner direset. Siap memindai lagi.');
  }

  void _onToggleTorch() {
    _scanner.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  /// Captures the current camera preview (texture), saves to [ManualEntryCaptureStore].
  Future<void> _onManualCapture() async {
    if (_manualCaptureBusy) return;
    setState(() => _manualCaptureBusy = true);
    try {
      if (!mounted) return;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;

      final previewContext = _cameraPreviewKey.currentContext;
      if (previewContext == null) {
        _showSnack('Pratinjau kamera belum siap. Coba lagi.');
        return;
      }

      // Context comes from GlobalKey after a short delay so the preview is painted.
      // ignore: use_build_context_synchronously
      final renderObject = previewContext.findRenderObject();
      final boundary = renderObject is RenderRepaintBoundary
          ? renderObject
          : null;
      if (boundary == null || !boundary.hasSize) {
        _showSnack('Gagal mengambil gambar. Coba lagi.');
        return;
      }

      final ui.Image image = await boundary.toImage(pixelRatio: dpr);
      try {
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) {
          _showSnack('Gagal mengode gambar.');
          return;
        }
        final bytes = byteData.buffer.asUint8List();
        final session = SessionContextStore.instance;
        final rec = await ManualEntryCaptureStore.instance.addCapture(
          imageBytes: bytes,
          source: widget.mode == ScanMode.transit
              ? ManualCaptureScanSource.transit
              : ManualCaptureScanSource.normal,
          userDisplay: session.displayUserId,
          scanPoint: session.scanPoint,
          airportCode: session.originCode,
        );
        if (!mounted) return;
        if (rec == null) {
          _showSnack('Gagal menyimpan foto.');
          return;
        }

        // Try decoding the barcode from the captured image file, then persist the
        // parsed fields as a draft for Manual Entry edits.
        try {
          final absPath =
              await ManualEntryCaptureStore.instance.fileAbsolutePath(rec);
          if (absPath.trim().isNotEmpty) {
            final capture = await _scanner.analyzeImage(absPath);
            final rawValue = (capture?.barcodes.isNotEmpty == true)
                ? capture!.barcodes.first.rawValue
                : null;
            if (rawValue != null && rawValue.trim().isNotEmpty) {
              final parsed = parseBCBP(rawValue.trim());
              if (parsed.isSuccess) {
                final name = parsed.name ?? parsed.passengerName ?? '';
                final date = parsed.flightDate ?? '';
                final seat = parsed.seatNumber ?? '';
                final origin = parsed.origin ?? parsed.originAirport ?? '';
                final destination =
                    parsed.destination ?? parsed.destinationAirport ?? '';
                final flight = parsed.flightNumber ?? parsed.airlineCode ?? '';
                final type = parsed.type ?? 'Adult';
                final category =
                    widget.mode == ScanMode.transit ? 'Transit' : 'Normal';

                await ManualEntryCaptureStore.instance.updateById(
                  rec.id,
                  rec.copyWith(
                    parsed: ManualEntryParsedDraft(
                      barcodeValue: rawValue.trim(),
                      passengerName: name.isEmpty ? 'N/A' : name,
                      boardingDate: date.isEmpty ? 'N/A' : date,
                      seat: seat.isEmpty ? 'N/A' : seat,
                      flight: flight.isEmpty ? 'N/A' : flight,
                      origin: origin.isEmpty ? 'N/A' : origin,
                      destination: destination.isEmpty ? 'N/A' : destination,
                      passengerType: type.isEmpty ? 'Adult' : type,
                      category: category,
                      scanPoint: session.scanPoint,
                    ),
                  ),
                );
              }
            }
          }
        } catch (e, st) {
          debugPrint('Manual capture analyzeImage failed: $e\n$st');
        }

        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Berhasil'),
            content: const Text(
              'Foto manual capture telah disimpan. Buka menu Manual Entry untuk '
              'melihat ringkasan dan detail file.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } finally {
        image.dispose();
      }
    } catch (e, st) {
      debugPrint('Manual capture failed: $e\n$st');
      if (mounted) {
        _showSnack('Gagal mengambil gambar. Coba lagi.');
      }
    } finally {
      if (mounted) {
        setState(() => _manualCaptureBusy = false);
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String get _pageTitle =>
      widget.mode == ScanMode.transit ? 'Scan Transit' : 'Scan Normal';

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentNav = widget.mode == ScanMode.transit
        ? PionaNavItem.scanTransit
        : PionaNavItem.scanNormal;
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        );
      },
      child: PionaShellScaffold(
        currentNav: currentNav,
        backgroundColor:
            isDark ? const Color(0xFF0D1117) : AppTheme.shellScaffoldLight,
        appBar: _buildAppBar(isDark),
        body: !_permissionChecked
            ? _buildPermissionLoading(context)
            : (_cameraPermission.isDenied ||
                    _cameraPermission.isPermanentlyDenied)
                ? _buildPermissionDenied(context)
                : _buildBody(context, isDark),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF161D2B) : AppTheme.primaryBlue,
      elevation: 0,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () {
          final nav = Navigator.of(context);
          if (nav.canPop()) {
            nav.pop();
          } else {
            nav.pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
            );
          }
        },
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _pageTitle,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
      actions: [
        // Mode badge
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: widget.mode == ScanMode.transit
                ? const Color(0xFFFBBF24).withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.mode == ScanMode.transit
                  ? const Color(0xFFFBBF24).withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            widget.mode == ScanMode.transit ? 'TRANSIT' : 'NORMAL',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: widget.mode == ScanMode.transit
                  ? const Color(0xFFFBBF24)
                  : Colors.white,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        32 + PionaFloatingNavBar.reserveBottomPadding(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Camera viewfinder ───────────────────────────────────────────
          _buildCameraCard(context, isDark),
          const SizedBox(height: 12),

          // ── Camera controls row ─────────────────────────────────────────
          _buildCameraControls(context, isDark),
          const SizedBox(height: 20),

          // ── Result card ─────────────────────────────────────────────────
          _buildResultCard(context, isDark),
          const SizedBox(height: 20),

          // ── Manual input section ────────────────────────────────────────
          _buildManualInputCard(context, isDark),
          const SizedBox(height: 14),

          // ── Upload TXT section ──────────────────────────────────────────
          _buildUploadCard(context, isDark),
        ],
      ),
    );
  }

  // ── Camera card ────────────────────────────────────────────────────────────

  Widget _buildCameraCard(BuildContext context, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1C2333) : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : AppTheme.primaryBlue.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Status header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: [
                _LiveIndicator(isScanning: _isScanning),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isScanning ? 'Siap Memindai' : 'Selesai',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimaryColor(context),
                        ),
                      ),
                      Text(
                        'PDF417 · IATA BCBP Format',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                // Scanning mode pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isScanning
                        ? AppTheme.validGreen.withValues(alpha: 0.12)
                        : AppTheme.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isScanning
                          ? AppTheme.validGreen.withValues(alpha: 0.3)
                          : AppTheme.primaryBlue.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    _isScanning ? 'LIVE' : 'PAUSED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _isScanning
                          ? AppTheme.validGreen
                          : AppTheme.primaryBlue,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Viewfinder
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(24)),
            child: SizedBox(
              height: 240,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Camera feed (RepaintBoundary enables preview snapshot)
                  RepaintBoundary(
                    key: _cameraPreviewKey,
                    child: MobileScanner(
                      controller: _scanner,
                      onDetect: _onBarcodeDetected,
                    ),
                  ),

                  // Dark vignette overlay
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.9,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.35),
                        ],
                      ),
                    ),
                  ),

                  // Scan frame + laser
                  Center(child: _buildScanFrame()),

                  // Corner hint text
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Arahkan barcode ke dalam kotak',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanFrame() {
    final laserAnim = _laserCtrl;
    return SizedBox(
      width: 290,
      height: 130,
      child: Stack(
        children: [
          // Border with corner decorations
          CustomPaint(
            size: const Size(290, 130),
            painter: _ScanFramePainter(color: AppTheme.validGreen),
          ),

          // Laser line
          if (laserAnim != null)
            ClipRect(
              child: AnimatedBuilder(
                animation: laserAnim,
                builder: (_, __) => CustomPaint(
                  size: const Size(290, 130),
                  painter: _LaserPainter(
                    color: AppTheme.validGreen,
                    value: laserAnim.value,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Camera controls ────────────────────────────────────────────────────────

  Widget _buildCameraControls(BuildContext context, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _ControlButton(
            icon: _torchOn ? Icons.flash_off_rounded : Icons.flash_on_rounded,
            label: _torchOn ? 'Flash Off' : 'Flash On',
            isDark: isDark,
            onTap: _onToggleTorch,
            accent: _torchOn ? const Color(0xFFFBBF24) : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ControlButton(
            icon: Icons.photo_camera_rounded,
            label: _manualCaptureBusy ? 'Memproses…' : 'Manual Capture',
            isDark: isDark,
            onTap: _onManualCapture,
            accent: AppTheme.primaryBlue,
            isLoading: _manualCaptureBusy,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ControlButton(
            icon: Icons.refresh_rounded,
            label: 'Reset',
            isDark: isDark,
            onTap: _onReset,
            accent: AppTheme.invalidRed,
          ),
        ),
      ],
    );
  }

  // ── Result card ────────────────────────────────────────────────────────────

  Widget _buildResultCard(BuildContext context, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1C2333) : Colors.white;

    return AnimatedSize(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.25)
                  : AppTheme.primaryBlue.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _lastResult == null
            ? _buildEmptyResult(context, isDark)
            : FadeTransition(
                opacity: _resultFade,
                child: SlideTransition(
                  position: _resultSlide,
                  child: _buildFilledResult(context, isDark, _lastResult!),
                ),
              ),
      ),
    );
  }

  Widget _buildEmptyResult(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color:
                  AppTheme.primaryBlue.withValues(alpha: isDark ? 0.15 : 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.document_scanner_outlined,
              size: 40,
              color: AppTheme.primaryBlue.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Hasil Scan',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimaryColor(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Detail boarding pass akan muncul di sini setelah berhasil dipindai',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondaryColor(context),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilledResult(
      BuildContext context, bool isDark, ScanResultDisplay r) {
    // Colors per status
    final statusColor = switch (r.status) {
      ParseStatus.complete => AppTheme.validGreen,
      ParseStatus.partial => const Color(0xFFF59E0B),
      ParseStatus.failed => AppTheme.invalidRed,
    };
    final statusBg = statusColor.withValues(alpha: isDark ? 0.18 : 0.1);
    final statusLabel = switch (r.status) {
      ParseStatus.complete => 'VALID — Data Lengkap',
      ParseStatus.partial => 'PERHATIAN — Data Tidak Lengkap',
      ParseStatus.failed => 'GAGAL — Tidak Dapat Diparsing',
    };
    final statusIcon = switch (r.status) {
      ParseStatus.complete => Icons.check_circle_rounded,
      ParseStatus.partial => Icons.warning_amber_rounded,
      ParseStatus.failed => Icons.cancel_rounded,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Status banner ───────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          decoration: BoxDecoration(
            color: statusBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              bottom: BorderSide(
                color: statusColor.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Text(
                '${r.scannedAt.hour.toString().padLeft(2, '0')}:${r.scannedAt.minute.toString().padLeft(2, '0')}:${r.scannedAt.second.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 10,
                  color: statusColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),

        // ── Warning strip (partial only) ────────────────────────────────────
        if (r.status == ParseStatus.partial && r.missingFields.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            color:
                const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.08 : 0.05),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 14, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Field tidak lengkap: ${r.missingFields.join(', ')}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Route header ────────────────────────────────────────────────────
        if (r.status != ParseStatus.failed) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            child: _buildRouteHeader(context, isDark, r),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Divider(height: 1),
          ),
        ],

        // ── Field grid ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: r.status == ParseStatus.failed
              ? _buildFailedBody(context, r)
              : _buildFieldGrid(context, isDark, r),
        ),
      ],
    );
  }

  Widget _buildRouteHeader(
      BuildContext context, bool isDark, ScanResultDisplay r) {
    return Row(
      children: [
        // Origin
        Expanded(
          child: Column(
            children: [
              Text(
                r.origin,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryBlue,
                  letterSpacing: 1,
                ),
              ),
              Text(
                'Asal',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
        // Flight arrow
        Column(
          children: [
            Icon(Icons.flight_rounded,
                color: AppTheme.primaryBlue.withValues(alpha: 0.5), size: 22),
            Container(
              width: 60,
              height: 1.5,
              color: AppTheme.primaryBlue.withValues(alpha: 0.2),
            ),
          ],
        ),
        // Destination
        Expanded(
          child: Column(
            children: [
              Text(
                r.destination,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryBlue,
                  letterSpacing: 1,
                ),
              ),
              Text(
                'Tujuan',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFieldGrid(
      BuildContext context, bool isDark, ScanResultDisplay r) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: _FieldCell(
                    label: 'Penumpang',
                    value: r.passengerName,
                    context: context)),
            const SizedBox(width: 12),
            Expanded(
                child: _FieldCell(
                    label: 'Maskapai', value: r.airlineCode, context: context)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child:
                    _FieldCell(label: 'Seat', value: r.seat, context: context)),
            const SizedBox(width: 12),
            Expanded(
                child:
                    _FieldCell(label: 'Gate', value: r.gate, context: context)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _FieldCell(
                    label: 'Tanggal', value: r.boardingDate, context: context)),
            const SizedBox(width: 12),
            Expanded(
                child: _FieldCell(
                    label: 'Boarding',
                    value: r.boardingTime,
                    context: context)),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(label: r.criteria, color: AppTheme.primaryBlue),
            _Chip(label: r.schedule, color: const Color(0xFF8B5CF6)),
          ],
        ),
      ],
    );
  }

  Widget _buildFailedBody(BuildContext context, ScanResultDisplay r) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.invalidRed.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppTheme.invalidRed.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: AppTheme.invalidRed, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Format barcode tidak dikenali atau data BCBP tidak valid.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondaryColor(context),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Manual input card ──────────────────────────────────────────────────────

  Widget _buildManualInputCard(BuildContext context, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1C2333) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.keyboard_rounded,
            label: 'Input Manual BCBP',
            subtitle: 'Tempel atau ketik raw data IATA BCBP',
            context: context,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _manualCtrl,
            maxLines: 4,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: AppTheme.textPrimaryColor(context),
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText:
                  'M1DOE/JOHN            E1234567 CGKDXB GA1234 123 1001Y011A0001 100',
              hintStyle: TextStyle(
                color:
                    AppTheme.textSecondaryColor(context).withValues(alpha: 0.5),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.black.withValues(alpha: 0.2)
                  : const Color(0xFFF4F6FB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.borderColor(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.borderColor(context)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: AppTheme.primaryBlue, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
            onSubmitted: (_) => _onManualSubmit(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    _manualCtrl.clear();
                  },
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  label: const Text('Hapus'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondaryColor(context),
                    side: BorderSide(color: AppTheme.borderColor(context)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _onManualSubmit,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Proses Data'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Upload card ────────────────────────────────────────────────────────────

  Widget _buildUploadCard(BuildContext context, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1C2333) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.upload_file_rounded,
            label: 'Upload File TXT',
            subtitle: 'Pilih file .txt berisi data boarding pass',
            context: context,
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _onUploadTxt,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : AppTheme.primaryBlue.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.03)
                      : AppTheme.primaryBlue.withValues(alpha: 0.02),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue
                            .withValues(alpha: isDark ? 0.15 : 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.cloud_upload_outlined,
                        size: 30,
                        color: AppTheme.primaryBlue
                            .withValues(alpha: isDark ? 0.9 : 0.7),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Ketuk untuk Pilih File',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Format .txt · Dari perangkat atau Google Drive',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondaryColor(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Permission views ───────────────────────────────────────────────────────

  Widget _buildPermissionLoading(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.primaryBlue),
          const SizedBox(height: 16),
          Text(
            'Memeriksa izin kamera...',
            style: TextStyle(
              color: AppTheme.textSecondaryColor(context),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDenied(BuildContext context) {
    final isPermanent = _cameraPermission.isPermanentlyDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.camera_alt_outlined,
                size: 48,
                color: AppTheme.primaryBlue.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Akses Kamera Diperlukan',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimaryColor(context),
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isPermanent
                  ? 'Izin kamera ditolak secara permanen. Aktifkan di Pengaturan perangkat untuk melanjutkan.'
                  : 'Aplikasi memerlukan akses kamera untuk memindai boarding pass.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondaryColor(context),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed:
                    isPermanent ? _openAppSettings : _requestCameraPermission,
                icon: Icon(
                  isPermanent
                      ? Icons.settings_rounded
                      : Icons.camera_alt_rounded,
                  size: 20,
                ),
                label: Text(isPermanent ? 'Buka Pengaturan' : 'Izinkan Kamera'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _LiveIndicator extends StatefulWidget {
  const _LiveIndicator({required this.isScanning});
  final bool isScanning;

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.isScanning ? AppTheme.validGreen : AppTheme.primaryBlue;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.4 + 0.6 * _c.value),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4 * _c.value),
              blurRadius: 6,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.accent,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  final Color? accent;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final fg = accent ?? AppTheme.textSecondaryColor(context);
    final bg = isDark ? const Color(0xFF1C2333) : Colors.white;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accent != null
                  ? accent!.withValues(alpha: 0.25)
                  : AppTheme.borderColor(context),
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 20,
                width: 20,
                child: isLoading
                    ? Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: fg,
                          ),
                        ),
                      )
                    : Icon(icon, color: fg, size: 20),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.context,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final BuildContext context;

  @override
  Widget build(BuildContext ctx) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.primaryBlue, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimaryColor(context),
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldCell extends StatelessWidget {
  const _FieldCell({
    required this.label,
    required this.value,
    required this.context,
  });

  final String label;
  final String value;
  final BuildContext context;

  @override
  Widget build(BuildContext ctx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMissing = value == 'N/A' || value == '—' || value.trim().isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFF4F6FB),
        borderRadius: BorderRadius.circular(12),
        border: isMissing
            ? Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: AppTheme.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isMissing
                  ? const Color(0xFFF59E0B)
                  : AppTheme.textPrimaryColor(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painters
// ─────────────────────────────────────────────────────────────────────────────

/// Draws a scan frame with styled corner brackets (airport terminal style).
class _ScanFramePainter extends CustomPainter {
  _ScanFramePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const corner = 22.0;
    final w = size.width;
    final h = size.height;

    // Top-left
    canvas.drawLine(Offset(0, corner), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(corner, 0), paint);
    // Top-right
    canvas.drawLine(Offset(w - corner, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, corner), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, h - corner), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(corner, h), paint);
    // Bottom-right
    canvas.drawLine(Offset(w - corner, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - corner), paint);
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter old) => old.color != color;
}

/// Animated laser sweep line.
class _LaserPainter extends CustomPainter {
  _LaserPainter({required this.color, required this.value});
  final Color color;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * value;
    final glowPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.6),
          color,
          color.withValues(alpha: 0.6),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
      ).createShader(Rect.fromLTWH(0, y - 4, size.width, 8))
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, y), Offset(size.width, y), glowPaint);
  }

  @override
  bool shouldRepaint(covariant _LaserPainter old) => old.value != value;
}
