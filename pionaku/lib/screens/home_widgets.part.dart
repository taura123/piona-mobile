part of 'home_screen.dart';

class _Orb extends StatelessWidget {
  const _Orb(this.size, this.color, this.opacity);
  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
              colors: [color.withOpacity(opacity), Colors.transparent]),
        ),
      );
}

class _DiagonalAccent extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _DiagPainter());
}

class _DiagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          HomeDesignTokens.accentCyan.withOpacity(0.08),
          Colors.transparent
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.6, 0)
      ..lineTo(size.width * 0.15, size.height);
    canvas.drawPath(path, p);
    final p2 = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          HomeDesignTokens.accentBlue.withOpacity(0.06),
          Colors.transparent
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final path2 = Path()
      ..moveTo(size.width * 0.8, 0)
      ..lineTo(size.width * 0.35, size.height);
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.size});
  final Color color;
  final double size;
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
                color: widget.color.withOpacity(0.5 * _ctrl.value),
                blurRadius: 6,
                spreadRadius: 2)
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// KPI Card
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _KpiData {
  const _KpiData(this.title, this.value, this.subtitle, this.subSub, this.icon,
      this.accent, this.trend, this.trendPct);
  final String title, value, subtitle;
  final String? subSub;
  final IconData icon;
  final Color accent;
  final KpiTrend trend;
  final double trendPct;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data, required this.isDark, this.shimmer});
  final _KpiData data;
  final bool isDark;
  final AnimationController? shimmer;

  @override
  Widget build(BuildContext context) {
    final trendColor = switch (data.trend) {
      KpiTrend.up => HomeDesignTokens.accentGreen,
      KpiTrend.down => const Color(0xFFFF5252),
      KpiTrend.flat => Colors.white54,
    };
    final trendIcon = switch (data.trend) {
      KpiTrend.up => Icons.trending_up_rounded,
      KpiTrend.down => Icons.trending_down_rounded,
      KpiTrend.flat => Icons.trending_flat_rounded,
    };

    return AspectRatio(
      aspectRatio: 1.1,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.09),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: data.accent.withOpacity(0.22)),
          boxShadow: [
            BoxShadow(
                color: data.accent.withOpacity(0.12),
                blurRadius: 16,
                offset: const Offset(0, 6)),
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: data.accent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: data.accent.withOpacity(0.3)),
                ),
                child: Icon(data.icon, size: 14, color: data.accent),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: trendColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(trendIcon, size: 10, color: trendColor),
                  const SizedBox(width: 2),
                  Text('${data.trendPct.abs().toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: trendColor)),
                ]),
              ),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.7))),
              const SizedBox(height: 3),
              FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(data.value,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: data.accent,
                          fontFeatures: const [FontFeature.tabularFigures()]))),
            ]),
            Text(data.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 9.5, color: Colors.white.withOpacity(0.55))),
            if (data.subSub != null)
              Text(data.subSub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 8.5, color: Colors.white.withOpacity(0.4))),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Section label
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(
      {required this.label, required this.icon, required this.isDark});
  final String label;
  final IconData icon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white : const Color(0xFF0A1628);
    final bg = isDark
        ? HomeDesignTokens.accentBlue.withOpacity(0.14)
        : HomeDesignTokens.accentBlue.withOpacity(0.09);
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: HomeDesignTokens.accentBlue, size: 16),
      ),
      const SizedBox(width: 10),
      Text(label,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: fg,
              letterSpacing: -0.2)),
      const SizedBox(width: 10),
      Expanded(
          child: Container(
              height: 1,
              decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                HomeDesignTokens.accentBlue.withOpacity(0.3),
                Colors.transparent
              ])))),
    ]);
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Scan card
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ScanCard extends StatefulWidget {
  const _ScanCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.accentColor,
    required this.pulseController,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final Color accentColor;
  final AnimationController pulseController;
  final VoidCallback onTap;

  @override
  State<_ScanCard> createState() => _ScanCardState();
}

class _ScanCardState extends State<_ScanCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeInOut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.gradientColors,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: widget.accentColor.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                  color: widget.gradientColors.first.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8)),
              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8),
            ],
          ),
          child: Row(children: [
            // Animated icon
            AnimatedBuilder(
              animation: widget.pulseController,
              builder: (_, __) {
                final s = 0.88 +
                    0.12 * math.sin(widget.pulseController.value * math.pi);
                return Transform.scale(
                  scale: s,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white.withOpacity(0.25)),
                      boxShadow: [
                        BoxShadow(
                            color: widget.accentColor.withOpacity(
                                0.3 * widget.pulseController.value),
                            blurRadius: 14,
                            spreadRadius: 2),
                      ],
                    ),
                    child: Icon(widget.icon, size: 28, color: Colors.white),
                  ),
                );
              },
            ),
            const SizedBox(width: 16),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.2)),
                  const SizedBox(height: 3),
                  Text(widget.subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.white.withOpacity(0.75))),
                ])),
            // Arrow chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: const Icon(Icons.arrow_forward_rounded,
                  size: 16, color: Colors.white),
            ),
          ]),
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Insight panel wrapper
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _InsightPanel extends StatelessWidget {
  const _InsightPanel(
      {required this.isDark,
      required this.title,
      required this.subtitle,
      required this.child});
  final bool isDark;
  final String title, subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? HomeDesignTokens.surfaceDark : Colors.white;
    final border = isDark ? HomeDesignTokens.borderDark(0.1) : HomeDesignTokens.borderLight(0.12);
    final shadow = isDark ? HomeDesignTokens.panelShadowDark : HomeDesignTokens.panelShadowLight;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
        boxShadow: shadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color:
                            isDark ? Colors.white : const Color(0xFF0A1628))),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38)),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: HomeDesignTokens.accentBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: HomeDesignTokens.accentBlue.withOpacity(0.2)),
            ),
            child: const Text('Harian',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: HomeDesignTokens.accentBlue)),
          ),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Flights table
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _TopFlightsTable extends StatelessWidget {
  const _TopFlightsTable({required this.isDark, required this.rows});
  final bool isDark;
  final List<HomeInsightFlightRoute> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty)
      return _EmptyState(isDark: isDark, label: 'No flight data yet.');
    final top5 = rows.take(5).toList();
    return Column(children: [
      _THead(isDark: isDark, cols: const ['FLIGHT', 'PAX', 'ROUTE', 'CHG']),
      const SizedBox(height: 6),
      ...top5.asMap().entries.map((entry) {
        final i = entry.key;
        final r = entry.value;
        final up = r.changePercent >= 0;
        return _TRow(
          isDark: isDark,
          rank: i + 1,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r.flight} · ${r.route} · ${r.passengers} pax'),
            behavior: SnackBarBehavior.floating,
          )),
          cells: [
            _MonoCell(r.flight, weight: FontWeight.w800, isDark: isDark),
            _MonoCell('${r.passengers}', isDark: isDark),
            _RouteCell(r.route, isDark: isDark),
            _ChangeCell(r.changePercent, up: up),
          ],
        );
      }),
    ]);
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Scan point table
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ScanPointTable extends StatelessWidget {
  const _ScanPointTable({required this.isDark, required this.rows});
  final bool isDark;
  final List<HomeInsightScanPoint> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty)
      return _EmptyState(isDark: isDark, label: 'No scan activity yet.');
    return Column(children: [
      _THead(isDark: isDark, cols: const ['SCAN POINT', 'PAX', '%', 'LOAD']),
      const SizedBox(height: 6),
      ...rows.asMap().entries.map((entry) {
        final i = entry.key;
        final r = entry.value;
        final pctText = '${(r.percent * 100).toStringAsFixed(0)}%';
        final badgeColor = r.workloadLabel == 'Highest'
            ? HomeDesignTokens.accentAmber
            : r.workloadLabel == 'High'
                ? const Color(0xFFFF5252)
                : r.workloadLabel == 'Medium'
                    ? HomeDesignTokens.accentBlue
                    : HomeDesignTokens.accentGreen;
        return _TRow(
          isDark: isDark,
          rank: i + 1,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${r.scanPoint} · ${r.passengers} pax · $pctText'),
            behavior: SnackBarBehavior.floating,
          )),
          cells: [
            _MonoCell(r.scanPoint, weight: FontWeight.w700, isDark: isDark),
            _MonoCell('${r.passengers}', isDark: isDark),
            _MonoCell(pctText, isDark: isDark),
            _BadgeCell(label: r.workloadLabel, color: badgeColor),
          ],
        );
      }),
      const SizedBox(height: 10),
      _WlLegend(isDark: isDark),
    ]);
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Table primitives
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _THead extends StatelessWidget {
  const _THead({required this.isDark, required this.cols});
  final bool isDark;
  final List<String> cols;

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white24 : Colors.black26;
    return Row(
        children: cols
            .map((c) => Expanded(
                child: Text(c,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 1))))
            .toList());
  }
}

class _TRow extends StatelessWidget {
  const _TRow(
      {required this.isDark,
      required this.rank,
      required this.cells,
      required this.onTap});
  final bool isDark;
  final int rank;
  final List<Widget> cells;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg =
        isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF7F9FF);
    final border =
        isDark ? Colors.white.withOpacity(0.07) : const Color(0xFFDDE6FF);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border)),
              child:
                  Row(children: cells.map((w) => Expanded(child: w)).toList()),
            ),
          )),
    );
  }
}

class _MonoCell extends StatelessWidget {
  const _MonoCell(this.text, {this.weight, required this.isDark});
  final String text;
  final FontWeight? weight;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Text(text,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: 12,
          fontWeight: weight ?? FontWeight.w500,
          color: isDark
              ? Colors.white.withOpacity(0.85)
              : const Color(0xFF1A2C52)));
}

class _RouteCell extends StatelessWidget {
  const _RouteCell(this.text, {required this.isDark});
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final parts = text.split('â€“');
    if (parts.length < 2) return _MonoCell(text, isDark: isDark);
    return Row(children: [
      Text(parts[0],
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? Colors.white.withOpacity(0.85)
                  : const Color(0xFF1A2C52))),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Icon(Icons.arrow_right_alt_rounded,
              size: 14, color: isDark ? Colors.white24 : Colors.black26)),
      Text(parts[1],
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? Colors.white.withOpacity(0.85)
                  : const Color(0xFF1A2C52))),
    ]);
  }
}

class _ChangeCell extends StatelessWidget {
  const _ChangeCell(this.value, {required this.up});
  final double value;
  final bool up;

  @override
  Widget build(BuildContext context) {
    final color = up ? HomeDesignTokens.accentGreen : const Color(0xFFFF5252);
    final sign = up ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6)),
      child: Text('$sign${value.toStringAsFixed(1)}%',
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class _BadgeCell extends StatelessWidget {
  const _BadgeCell({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.25))),
        child: Text(label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: color)),
      );
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Hourly chart
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _HourlyFlowChart extends StatelessWidget {
  const _HourlyFlowChart(
      {required this.isDark,
      required this.points,
      required this.selectedIndex,
      required this.onSelect});
  final bool isDark;
  final List<HomeInsightHourlyFlowPoint> points;
  final int? selectedIndex;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty)
      return _EmptyState(isDark: isDark, label: 'No hourly data yet.');

    final maxV = points
        .map((e) => e.passengers)
        .fold<int>(0, math.max)
        .clamp(1, 1 << 30);
    final sel = (selectedIndex != null &&
            selectedIndex! >= 0 &&
            selectedIndex! < points.length)
        ? points[selectedIndex!]
        : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Detail tooltip
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: sel != null
            ? Container(
                key: ValueKey(sel.hourLabel),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    HomeDesignTokens.accentBlue.withOpacity(0.15),
                    HomeDesignTokens.accentCyan.withOpacity(0.08)
                  ]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HomeDesignTokens.accentBlue.withOpacity(0.25)),
                ),
                child: Row(children: [
                  Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: HomeDesignTokens.accentBlue.withOpacity(0.2),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.access_time_rounded,
                          size: 14, color: HomeDesignTokens.accentBlue)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          '${sel.hourLabel}  ·  ${sel.passengers} penumpang',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0A1628)))),
                  GestureDetector(
                      onTap: () => onSelect(null),
                      child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.06),
                              shape: BoxShape.circle),
                          child: Icon(Icons.close_rounded,
                              size: 14,
                              color:
                                  isDark ? Colors.white54 : Colors.black38))),
                ]),
              )
            : const SizedBox.shrink(),
      ),
      SizedBox(
        height: 165,
        child: _BarChart(
            isDark: isDark,
            points: points,
            maxValue: maxV,
            selectedIndex: selectedIndex,
            onSelect: onSelect),
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.touch_app_rounded,
            size: 12, color: isDark ? Colors.white30 : Colors.black26),
        const SizedBox(width: 5),
        Text('Tap any bar to view passenger detail',
            style: TextStyle(
                fontSize: 11, color: isDark ? Colors.white30 : Colors.black38)),
      ]),
    ]);
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart(
      {required this.isDark,
      required this.points,
      required this.maxValue,
      required this.selectedIndex,
      required this.onSelect});
  final bool isDark;
  final List<HomeInsightHourlyFlowPoint> points;
  final int maxValue;
  final int? selectedIndex;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final count = points.length.clamp(1, 200);
      const gap = 3.0;
      final barW = ((w - gap * (count - 1)) / count).clamp(2.0, 20.0);

      int? hitTest(double dx) {
        var x = 0.0;
        for (var i = 0; i < count; i++) {
          if (dx >= x && dx <= x + barW) return i;
          x += barW + gap;
        }
        return null;
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => onSelect(hitTest(d.localPosition.dx)),
        child: CustomPaint(
          painter: _BarPainter(
            points: points,
            maxValue: maxValue,
            barWidth: barW,
            gap: gap,
            barColor:
                isDark ? const Color(0xFF3D7FFF) : const Color(0xFF2B5CE6),
            barColorAlt:
                isDark ? const Color(0xFF00C8E8) : const Color(0xFF0A6EA8),
            selectedColor: HomeDesignTokens.accentAmber,
            selectedIndex: selectedIndex,
            axisColor: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.06),
            textColor: isDark ? Colors.white38 : Colors.black38,
          ),
          size: Size(w, h),
        ),
      );
    });
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.points,
    required this.maxValue,
    required this.barWidth,
    required this.gap,
    required this.barColor,
    required this.barColorAlt,
    required this.selectedColor,
    required this.selectedIndex,
    required this.axisColor,
    required this.textColor,
  });

  final List<HomeInsightHourlyFlowPoint> points;
  final int maxValue;
  final double barWidth, gap;
  final Color barColor, barColorAlt, selectedColor, axisColor, textColor;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    const botPad = 22.0, topPad = 8.0;
    final chartH = (size.height - botPad - topPad).clamp(10.0, 1000.0);
    final baseY = topPad + chartH;
    final count = points.length;

    // Grid
    final gridP = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), gridP);
    for (var i = 1; i <= 3; i++) {
      final y = topPad + chartH * (1 - i / 4);
      canvas.drawLine(
          Offset(0, y), Offset(size.width, y), gridP..color = axisColor);
    }

    final labelEvery = math.max(1, (count / 6).round());
    var x = 0.0;

    // Pre-compute line points (center of each bar).
    final lineOffsets = <Offset>[];

    for (var i = 0; i < count; i++) {
      final v = points[i].passengers;
      final t = (v / maxValue).clamp(0.0, 1.0);
      final bh = (t * chartH).clamp(v > 0 ? 2.0 : 0.0, chartH);
      final top = baseY - bh;
      final r = const Radius.circular(4);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, top, barWidth, bh),
        topLeft: r,
        topRight: r,
      );

      final bool isSel = selectedIndex == i;
      if (isSel) {
        canvas.save();
        canvas.drawRRect(
            rect.inflate(2),
            Paint()
              ..color = selectedColor.withOpacity(0.2)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        canvas.restore();
      }

      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isSel
              ? [selectedColor, selectedColor.withOpacity(0.5)]
              : [barColor, barColorAlt.withOpacity(0.6)],
        ).createShader(Rect.fromLTWH(x, top, barWidth, bh));

      canvas.drawRRect(rect, paint);

      lineOffsets.add(Offset(x + barWidth / 2, top));

      if (i % labelEvery == 0 || i == count - 1) {
        final tp = TextPainter(
          text: TextSpan(
              text: points[i].hourLabel,
              style: TextStyle(
                  fontSize: 8.5,
                  color: isSel ? selectedColor : textColor,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w400)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 40);
        tp.paint(canvas, Offset(x + barWidth / 2 - tp.width / 2, baseY + 5));
      }

      x += barWidth + gap;
    }

    // Line chart overlay (trend).
    if (lineOffsets.isNotEmpty) {
      final path = Path()..moveTo(lineOffsets.first.dx, lineOffsets.first.dy);
      for (var i = 1; i < lineOffsets.length; i += 1) {
        final p0 = lineOffsets[i - 1];
        final p1 = lineOffsets[i];
        final cx = (p0.dx + p1.dx) / 2;
        path.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
      }

      final glow = Paint()
        ..color = (selectedColor).withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, glow);

      final stroke = Paint()
        ..color = selectedColor.withOpacity(0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, stroke);

      final dotP = Paint()..color = selectedColor.withOpacity(0.95);
      for (var i = 0; i < lineOffsets.length; i += 1) {
        final r = selectedIndex == i ? 4.0 : 2.6;
        canvas.drawCircle(lineOffsets[i], r, dotP);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.points != points ||
      old.selectedIndex != selectedIndex ||
      old.maxValue != maxValue;
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Empty state
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isDark, required this.label});
  final bool isDark;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.03)
            : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.07)
                : Colors.black.withOpacity(0.05)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.inbox_rounded,
            size: 20, color: isDark ? Colors.white24 : Colors.black26),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white38 : Colors.black38)),
      ]),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Workload legend
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _WlLegend extends StatelessWidget {
  const _WlLegend({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String l) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 5),
          Text(l,
              style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? Colors.white38 : Colors.black38)),
        ]);

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        item(HomeDesignTokens.accentAmber, 'Highest'),
        item(const Color(0xFFFF5252), 'High'),
        item(HomeDesignTokens.accentBlue, 'Medium'),
        item(HomeDesignTokens.accentGreen, 'Low'),
      ],
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Info banner
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? HomeDesignTokens.accentBlue.withOpacity(0.08)
            : HomeDesignTokens.accentBlue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HomeDesignTokens.accentBlue.withOpacity(0.18)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: HomeDesignTokens.accentBlue.withOpacity(0.12), shape: BoxShape.circle),
          child: const Icon(Icons.info_outline_rounded,
              color: HomeDesignTokens.accentBlue, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(
          'Pastikan barcode boarding pass dalam kondisi jelas dan tidak rusak untuk hasil scan optimal.',
          style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white54 : Colors.black54,
              height: 1.45),
        )),
      ]),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Small reusable widgets
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withOpacity(0.12),
        shape: const CircleBorder(),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(icon, size: 18, color: Colors.white))),
      );
}

/// Logo + label on the home top bar; tap opens profile (same as before).
class _HomeTopBrandProfile extends StatelessWidget {
  const _HomeTopBrandProfile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 10, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: Image.asset(
                  'assets/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'PIONA MOBILE',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.9,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
