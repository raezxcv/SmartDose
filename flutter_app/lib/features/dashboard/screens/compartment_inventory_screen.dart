import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'alerts_tab.dart';
import 'package:smartdose/shared/widgets/smartdose_loading.dart';

class CompartmentInventoryScreen extends StatelessWidget {
  final bool isCaregiver;
  final String? patientUid;
  const CompartmentInventoryScreen({super.key, this.isCaregiver = false, this.patientUid});

  Stream<QuerySnapshot<Map<String, dynamic>>> get _compartmentsStream {
    if (patientUid != null && patientUid!.isNotEmpty) {
      return FirebaseFirestore.instance
          .collection('compartments')
          .where('patientUid', isEqualTo: patientUid)
          .snapshots();
    }
    return FirebaseFirestore.instance
        .collection('compartments')
        .snapshots();
  }

  Future<void> _refillCompartment(
      BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final name = data?['medicationName'] ?? 'Medication';
    final maxCapacity = data?['maxCapacity'] as int? ?? 30;

    await doc.reference.update({
      'stockCount': maxCapacity,
      'lastRefilledAt': FieldValue.serverTimestamp(),
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name refilled to $maxCapacity pills!'),
          backgroundColor: const Color(0xFF00A36C),
        ),
      );
    }
  }

  Future<void> _showUpdateMedNameSheet(
      BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data() ?? {};
    final nameCtrl = TextEditingController(text: data['medicationName'] ?? '');
    final maxCtrl = TextEditingController(text: (data['maxCapacity'] ?? 30).toString());

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Edit Compartment ${data['compartmentNumber'] ?? ''}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Medication Name',
                prefixIcon: const Icon(Icons.medication_outlined, color: Color(0xFF00A36C)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: maxCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Max Capacity (pills)',
                prefixIcon: const Icon(Icons.numbers_rounded, color: Color(0xFF00A36C)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A36C),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  elevation: 0,
                ),
                onPressed: () async {
                  final newName = nameCtrl.text.trim();
                  final maxCap = int.tryParse(maxCtrl.text.trim()) ?? 30;
                  if (newName.isNotEmpty) {
                    await doc.reference.update({
                      'medicationName': newName,
                      'maxCapacity': maxCap,
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save Changes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Medicine Inventory', style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor)),
        backgroundColor: cardBgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: primaryTextColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.bell, color: primaryTextColor, size: 20),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PatientAlertsTab()),
              );
            },
            tooltip: 'Notifications',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _compartmentsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: SmartDoseLoading(size: 140));
          }

          final rawDocs = snapshot.data?.docs ?? [];
          final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(rawDocs)
            ..sort((a, b) {
              final aNum = a.data()['compartmentNumber'] as int? ?? int.tryParse(a.id.replaceAll(RegExp(r'\D'), '')) ?? 0;
              final bNum = b.data()['compartmentNumber'] as int? ?? int.tryParse(b.id.replaceAll(RegExp(r'\D'), '')) ?? 0;
              return aNum.compareTo(bNum);
            });

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 64, color: secondaryTextColor.withValues(alpha: 0.4)),
                    const SizedBox(height: 20),
                    Text(
                      'No compartments found',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Compartment data will appear here once your SmartDose Dispenser is paired and configured.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
            );
          }

          // Summary header
          final totalLow = docs.where((d) => (d.data()['stockCount'] as int? ?? 0) <= 3).length;
          final totalEmpty = docs.where((d) => (d.data()['stockCount'] as int? ?? 0) == 0).length;

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length + 1, // +1 for summary header
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildSummaryHeader(docs.length, totalLow, totalEmpty);
              }

              final doc = docs[index - 1];
              final data = doc.data();
              final compNum = data['compartmentNumber'] ?? index;
              final medName = data['medicationName'];
              final stock = data['stockCount'] as int? ?? 0;
              final maxCap = data['maxCapacity'] as int? ?? 30;
              final progress = maxCap > 0 ? (stock / maxCap).clamp(0.0, 1.0) : 0.0;
              final isLow = stock <= 3 && stock > 0;
              final isEmpty = stock == 0;
              final lastRefilled = data['lastRefilledAt'] as Timestamp?;
              final refilledStr = lastRefilled != null
                  ? DateFormat('MMM d, hh:mm a').format(lastRefilled.toDate())
                  : null;

              Color borderColor = isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB);
              Color barColor = const Color(0xFF00A36C);
              if (isEmpty) {
                borderColor = const Color(0xFFFCA5A5);
                barColor = const Color(0xFFEF4444);
              } else if (isLow) {
                borderColor = const Color(0xFFFBBF24);
                barColor = const Color(0xFFF59E0B);
              }

              return GestureDetector(
                onTap: isCaregiver ? () => _showUpdateMedNameSheet(context, doc) : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderColor, width: (isLow || isEmpty) ? 1.5 : 1),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03), blurRadius: 10, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6F7F0),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Comp $compNum',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF00A36C)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                medName ?? 'Unassigned',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: medName != null ? primaryTextColor : secondaryTextColor,
                                ),
                              ),
                            ],
                          ),
                          if (isEmpty)
                            _statusBadge('Empty', const Color(0xFFEF4444), const Color(0xFFFEE2E2))
                          else if (isLow)
                            _statusBadge('Low Stock', const Color(0xFFD97706), const Color(0xFFFEF3C7)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 10,
                                backgroundColor: const Color(0xFFF3F4F6),
                                valueColor: AlwaysStoppedAnimation<Color>(barColor),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            '$stock / $maxCap pills',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4B5563)),
                          ),
                        ],
                      ),
                      if (refilledStr != null) ...[
                        const SizedBox(height: 6),
                        Text('Last refilled: $refilledStr',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                      ],
                      if (isCaregiver) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(foregroundColor: const Color(0xFF6B7280)),
                              onPressed: () => _showUpdateMedNameSheet(context, doc),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Edit', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              style: TextButton.styleFrom(foregroundColor: const Color(0xFF00A36C)),
                              onPressed: () => _refillCompartment(context, doc),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Refill', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSummaryHeader(int total, int lowCount, int emptyCount) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF00A36C), Color(0xFF00C882)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('$total', 'Total Comps', Icons.grid_view_rounded),
          _summaryDivider(),
          _summaryItem('${total - lowCount - emptyCount}', 'Well stocked', Icons.check_circle_rounded),
          _summaryDivider(),
          _summaryItem('$lowCount', 'Low stock', Icons.warning_amber_rounded),
          _summaryDivider(),
          _summaryItem('$emptyCount', 'Empty', Icons.remove_circle_outline_rounded),
        ],
      ),
    );
  }

  Widget _summaryItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _summaryDivider() {
    return Container(width: 1, height: 40, color: Colors.white24);
  }

  Widget _statusBadge(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
    );
  }
}
