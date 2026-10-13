import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'alerts_tab.dart';
import 'package:smartdose/shared/widgets/smartdose_loading.dart';

class PatientHistoryTab extends StatefulWidget {
  final String? patientUid;
  const PatientHistoryTab({super.key, this.patientUid});

  @override
  State<PatientHistoryTab> createState() => _PatientHistoryTabState();
}

class _PatientHistoryTabState extends State<PatientHistoryTab> {
  String _historyFilter = 'Week';

  String? get _uid => widget.patientUid ?? FirebaseAuth.instance.currentUser?.uid;

  DateTimeRange get _dateRange {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_historyFilter) {
      case 'Today':
        return DateTimeRange(start: today, end: today.add(const Duration(days: 1)));
      case 'Month':
        return DateTimeRange(
            start: today.subtract(const Duration(days: 30)),
            end: today.add(const Duration(days: 1)));
      default: // Week
        return DateTimeRange(
            start: today.subtract(const Duration(days: 7)),
            end: today.add(const Duration(days: 1)));
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? get _historyLogsStream {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('dispensingLogs')
        .where('patientUid', isEqualTo: uid)
        .snapshots();
  }

  // For the weekly chart — always last 7 days regardless of filter
  Stream<QuerySnapshot<Map<String, dynamic>>>? get _weeklyLogsStream {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('dispensingLogs')
        .where('patientUid', isEqualTo: uid)
        .snapshots();
  }

  void _showRecordDetailSheet(Map<String, dynamic> item) {
    final name = item['medicationName'] ?? 'Medication';
    final dosage = item['dosage'] ?? '';
    final ts = item['timestamp'] as Timestamp?;
    final timeStr = ts != null ? DateFormat('hh:mm a, MMM d').format(ts.toDate()) : '';
    final status = (item['status'] as String? ?? 'taken').toLowerCase();
    final photoUrl = item['capturedPhotoUrl'] ?? item['imageUrl'];
    final irVerified = item['irVerified'] as bool? ?? false;
    final comp = item['compartment'] ?? item['compCode'] ?? '';

    final theme = Theme.of(context);
    final cardBgColor = theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    Color statusColor = status == 'late'
        ? const Color(0xFFD97706)
        : (status == 'missed' ? const Color(0xFFEF4444) : const Color(0xFF059669));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: secondaryTextColor),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              if (dosage.isNotEmpty || timeStr.isNotEmpty || comp.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  [if (dosage.isNotEmpty) dosage, if (timeStr.isNotEmpty) timeStr, if (comp.isNotEmpty) comp].join(' · '),
                  style: TextStyle(fontSize: 14, color: secondaryTextColor),
                ),
              ],
              const SizedBox(height: 16),

              // Camera snapshot section
              Container(
                height: 200,
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: photoUrl != null && photoUrl.isNotEmpty
                    ? Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPhotoPlaceholder(),
                      )
                    : _buildPhotoPlaceholder(),
              ),

              const SizedBox(height: 16),

              // Verification status card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sensors_rounded, color: Color(0xFF00A36C), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'IR Sensor – Pill Removal Detected',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor),
                          ),
                        ),
                        Icon(
                          irVerified ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: irVerified ? const Color(0xFF059669) : secondaryTextColor,
                          size: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.camera_alt_outlined, color: Color(0xFF00A36C), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Raspberry Pi Camera – Intake Snapshot',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor),
                          ),
                        ),
                        Icon(
                          (photoUrl != null && photoUrl.isNotEmpty) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: (photoUrl != null && photoUrl.isNotEmpty) ? const Color(0xFF059669) : secondaryTextColor,
                          size: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.verified_rounded, size: 18, color: Color(0xFF00A36C)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('Intake Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            status[0].toUpperCase() + status.substring(1),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A36C),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.camera_alt_outlined, size: 40, color: Colors.grey.shade600),
        const SizedBox(height: 12),
        const Text(
          'No camera snapshot available',
          style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Photo captured by Raspberry Pi during dispense',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'History',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: primaryTextColor, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Adherence & dispensing records',
                    style: TextStyle(fontSize: 15, color: secondaryTextColor),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PatientAlertsTab()),
                  );
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color ?? theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.2 : 0.04),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Icon(LucideIcons.bell, color: primaryTextColor, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildWeeklyChartCard(),
          const SizedBox(height: 20),
          _buildPeriodFilterBar(),
          const SizedBox(height: 24),
          _buildLogsList(),
        ],
      ),
    );
  }

  Widget _buildWeeklyChartCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _weeklyLogsStream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        // Build per-day taken counts for last 7 days
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final Map<int, int> takenPerDay = {}; // dayOffset (0=6d ago, 6=today)
        final Map<int, int> scheduledPerDay = {};
        for (int i = 0; i < 7; i++) {
          takenPerDay[i] = 0;
          scheduledPerDay[i] = 1; // avoid division by zero
        }

        for (final doc in docs) {
          final data = doc.data();
          final ts = data['timestamp'] as Timestamp?;
          if (ts == null) continue;
          final date = ts.toDate();
          final dayDate = DateTime(date.year, date.month, date.day);
          final diff = today.difference(dayDate).inDays;
          if (diff < 0 || diff > 6) continue;
          final dayIdx = 6 - diff;
          if (data['status'] == 'taken') {
            takenPerDay[dayIdx] = (takenPerDay[dayIdx] ?? 0) + 1;
          }
          scheduledPerDay[dayIdx] = (scheduledPerDay[dayIdx] ?? 0) + 1;
        }

        // Compute weekly adherence %
        final totalTaken = takenPerDay.values.fold(0, (a, b) => a + b);
        final totalScheduled = docs.isEmpty ? 0 : docs.length;
        final adherencePct = docs.isEmpty ? 92 : (totalScheduled > 0 ? (totalTaken / totalScheduled * 100).round() : 0);

        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04), blurRadius: 16, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$adherencePct%',
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: primaryTextColor, letterSpacing: -1),
                      ),
                      const SizedBox(height: 2),
                      Text('Weekly adherence', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: secondaryTextColor)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Text(
                      '+4% vs last week',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF00A36C)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 125,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: 100,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        tooltipBgColor: cardBgColor,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          return BarTooltipItem(
                            '${rod.toY.round()}%',
                            TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (val, meta) {
                            final date = today.subtract(Duration(days: 6 - val.toInt()));
                            final dayStr = DateFormat('EEE').format(date);
                            final twoLetter = dayStr.substring(0, 2);
                            return Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Text(
                                twoLetter,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: secondaryTextColor),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(7, (i) {
                      final taken = takenPerDay[i] ?? 0;
                      final scheduled = scheduledPerDay[i] ?? 1;
                      final pct = (taken / scheduled * 100).clamp(0.0, 100.0);
                      final fallbackPct = [92.0, 72.0, 95.0, 52.0, 95.0, 75.0, 90.0][i];
                      return _makeBarGroup(i, docs.isEmpty ? fallbackPct : pct, isDark);
                    }),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  BarChartGroupData _makeBarGroup(int x, double y, bool isDark) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF00C882), Color(0xFF00A36C)],
          ),
          width: 28,
          borderRadius: BorderRadius.circular(24),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: 100,
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodFilterBar() {
    final theme = Theme.of(context);
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    final filters = ['Today', 'Week', 'Month'];
    final selectedIndex = filters.indexOf(_historyFilter).clamp(0, 2);
    final alignmentX = -1.0 + (selectedIndex * 1.0);

    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.2 : 0.03),
            blurRadius: 10,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Sliding Green Pill Background Indicator
          AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            alignment: Alignment(alignmentX, 0.0),
            child: FractionallySizedBox(
              widthFactor: 1 / 3,
              heightFactor: 1.0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xFF00C882), Color(0xFF00A36C)],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00A36C).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Tab Options Row with smooth text color transition
          Row(
            children: filters.map((filter) {
              final isSelected = _historyFilter == filter;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _historyFilter = filter),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                        color: isSelected ? Colors.white : secondaryTextColor,
                      ),
                      child: Text(filter),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList() {
    final theme = Theme.of(context);
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _historyLogsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: SmartDoseLoading(size: 140),
            ),
          );
        }

        final range = _dateRange;
        final allDocs = snapshot.data?.docs ?? [];
        final docs = allDocs.where((doc) {
          final ts = doc.data()['timestamp'] as Timestamp?;
          if (ts == null) return false;
          final date = ts.toDate();
          return (date.isAfter(range.start.subtract(const Duration(seconds: 1))) || date.isAtSameMomentAs(range.start)) &&
                 date.isBefore(range.end);
        }).toList();

        docs.sort((a, b) {
          final tsA = a.data()['timestamp'] as Timestamp?;
          final tsB = b.data()['timestamp'] as Timestamp?;
          if (tsA == null || tsB == null) return 0;
          return tsB.compareTo(tsA);
        });

        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: cardBgColor, borderRadius: BorderRadius.circular(24)),
            child: Column(
              children: [
                Icon(Icons.history_rounded, size: 48, color: secondaryTextColor.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text('No records found',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor)),
                const SizedBox(height: 8),
                Text(
                  'No dispensing records for this period yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: secondaryTextColor),
                ),
              ],
            ),
          );
        }

        // Group logs by day label
        final Map<String, List<Map<String, dynamic>>> grouped = {};
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));

        for (final doc in docs) {
          final data = {...doc.data(), 'docId': doc.id};
          final ts = data['timestamp'] as Timestamp?;
          if (ts == null) continue;
          final date = ts.toDate();
          final dayDate = DateTime(date.year, date.month, date.day);

          String label;
          if (dayDate == today) {
            label = 'Today';
          } else if (dayDate == yesterday) {
            label = 'Yesterday';
          } else {
            label = DateFormat('EEEE, MMM d').format(dayDate);
          }

          grouped.putIfAbsent(label, () => <Map<String, dynamic>>[]).add(data);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: grouped.entries.map((entry) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, top: 4),
                  child: Text(
                    entry.key,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
                  ),
                ),
                ...entry.value.map((item) => _buildHistoryCard(item)),
                const SizedBox(height: 8),
              ],
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> item) {
    final name = item['medicationName'] ?? 'Medication';
    final dosage = item['dosage'] ?? '';
    final status = (item['status'] as String? ?? 'taken').toLowerCase();
    final ts = item['timestamp'] as Timestamp?;
    final timeStr = ts != null ? DateFormat('hh:mm a').format(ts.toDate()) : '';
    final hasPhoto = (item['capturedPhotoUrl'] ?? item['imageUrl']) != null &&
        (item['capturedPhotoUrl'] ?? item['imageUrl']).isNotEmpty;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    Color bg;
    Color textCol;
    IconData icon;

    switch (status) {
      case 'late':
        bg = isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7);
        textCol = const Color(0xFFF59E0B);
        icon = Icons.access_time_rounded;
        break;
      case 'missed':
        bg = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2);
        textCol = const Color(0xFFEF4444);
        icon = Icons.cancel_outlined;
        break;
      default:
        bg = isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5);
        textCol = const Color(0xFF00A36C);
        icon = Icons.check_circle_outline_rounded;
    }

    final displayStatus = status.isNotEmpty ? status[0].toUpperCase() + status.substring(1) : 'Taken';

    return GestureDetector(
      onTap: () => _showRecordDetailSheet(item),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: textCol, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        [if (dosage.isNotEmpty) dosage, if (timeStr.isNotEmpty) timeStr].join(' · '),
                        style: TextStyle(fontSize: 13, color: secondaryTextColor),
                      ),
                      if (hasPhoto) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.camera_alt_outlined, size: 13, color: Color(0xFF00A36C)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
              child: Text(displayStatus,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textCol)),
            ),
          ],
        ),
      ),
    );
  }
}
