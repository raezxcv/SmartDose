import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'alerts_tab.dart';
import 'package:smartdose/shared/widgets/smartdose_loading.dart';

class PatientMedsTab extends StatefulWidget {
  final bool isCaregiver;
  final String? patientUid;
  final String initialSection;
  final bool isStandalone;

  const PatientMedsTab({
    super.key,
    this.isCaregiver = false,
    this.patientUid,
    this.initialSection = 'schedule',
    this.isStandalone = false,
  });

  @override
  State<PatientMedsTab> createState() => _PatientMedsTabState();
}

class _PatientMedsTabState extends State<PatientMedsTab> {
  int _selectedDateIndex = 0;
  late List<DateTime> _weekDays;
  late String _selectedSection;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _schedulesStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _compartmentsStream;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestCompartmentDocs = [];

  String? get _uid => widget.patientUid ?? FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _selectedSection = widget.initialSection;
    _generateWeekDays();
    _initStreams();
  }

  @override
  void didUpdateWidget(PatientMedsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientUid != widget.patientUid) {
      _initStreams();
    }
    if (oldWidget.initialSection != widget.initialSection) {
      setState(() => _selectedSection = widget.initialSection);
    }
  }

  void _initStreams() {
    final uid = _uid;
    if (uid != null && uid.isNotEmpty) {
      _schedulesStream = FirebaseFirestore.instance
          .collection('schedules')
          .where('patientUid', isEqualTo: uid)
          .snapshots();

      _compartmentsStream = FirebaseFirestore.instance
          .collection('compartments')
          .where('patientUid', isEqualTo: uid)
          .snapshots();
    } else {
      _schedulesStream = null;
      _compartmentsStream = null;
    }
  }

  void _generateWeekDays() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    _weekDays = List.generate(7, (i) => monday.add(Duration(days: i)));
    final todayIndex = _weekDays.indexWhere((d) =>
        d.year == now.year && d.month == now.month && d.day == now.day);
    if (todayIndex != -1) _selectedDateIndex = todayIndex;
  }

  DateTime get _selectedDate => _weekDays[_selectedDateIndex];

  // ─────────────────────────────────────────────────────────────────────────
  // Medication Schedule Setup (Workflow Step 2: From Configured Inventory)
  // ─────────────────────────────────────────────────────────────────────────

  void _showMedicationSheet({DocumentSnapshot<Map<String, dynamic>>? editDoc}) {
    final isEditing = editDoc != null;
    final editData = editDoc?.data();

    // Filter only occupied/configured compartments from Pill Inventory
    final availableComps = _latestCompartmentDocs.where((doc) {
      final name = (doc.data()['medicationName'] as String? ?? '').trim();
      return name.isNotEmpty;
    }).toList();

    if (availableComps.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: Color(0xFFF59E0B)),
              SizedBox(width: 10),
              Text('Inventory Setup Needed'),
            ],
          ),
          content: const Text(
            'Before creating a medication schedule, please configure at least one compartment in the Pill Inventory first. Each schedule links directly to an active compartment.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A36C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _selectedSection = 'inventory');
              },
              child: const Text('Go to Pill Inventory', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    // Determine initial selection
    QueryDocumentSnapshot<Map<String, dynamic>> selectedCompDoc = availableComps.first;
    if (isEditing && editData?['compCode'] != null) {
      final existingCode = editData!['compCode'] as String;
      final match = availableComps.where((c) {
        final cNum = c.data()['compartmentNumber'] ?? c.id.replaceAll(RegExp(r'\D'), '');
        return 'C$cNum' == existingCode || c.data()['compCode'] == existingCode;
      }).firstOrNull;
      if (match != null) selectedCompDoc = match;
    }

    String selectedCompCode = 'C${selectedCompDoc.data()['compartmentNumber'] ?? selectedCompDoc.id.replaceAll(RegExp(r'\D'), '')}';
    String medName = selectedCompDoc.data()['medicationName'] ?? '';
    String dosage = selectedCompDoc.data()['dosage'] ?? '1 tablet';

    TimeOfDay selectedTime = TimeOfDay(
      hour: editData?['scheduledTime'] != null
          ? (editData!['scheduledTime'] as Timestamp).toDate().hour
          : 8,
      minute: editData?['scheduledTime'] != null
          ? (editData!['scheduledTime'] as Timestamp).toDate().minute
          : 0,
    );
    String selectedFreq = editData?['frequency'] ?? 'Daily';

    final cardBgColor = Theme.of(context).colorScheme.surface;
    final primaryTextColor = Theme.of(context).colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
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
                    Text(
                      isEditing ? 'Edit Schedule' : 'Schedule Medication',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                    if (isEditing)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                        tooltip: 'Delete Schedule',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: ctx,
                            builder: (dialogCtx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              title: const Text('Delete Schedule?'),
                              content: Text('Remove $medName from this schedule?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                  onPressed: () => Navigator.pop(dialogCtx, true),
                                  child: const Text('Delete', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await editDoc.reference.delete();
                            if (ctx.mounted) Navigator.pop(ctx);
                          }
                        },
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Schedules reference configured medications directly from your Pill Inventory.',
                  style: TextStyle(fontSize: 13, color: secondaryTextColor),
                ),
                const SizedBox(height: 20),

                // Compartment Selection Dropdown (Only occupied compartments selectable)
                Text('Select Compartment', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedCompCode,
                  dropdownColor: cardBgColor,
                  style: TextStyle(color: primaryTextColor, fontSize: 15),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(LucideIcons.boxes, color: Color(0xFF00A36C)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  items: availableComps.map((c) {
                    final cData = c.data();
                    final cNum = cData['compartmentNumber'] ?? c.id.replaceAll(RegExp(r'\D'), '');
                    final code = 'C$cNum';
                    final name = cData['medicationName'] ?? 'Medication';
                    final dose = cData['dosage'] ?? '';
                    final label = '$code: $name${dose.isNotEmpty ? ' ($dose)' : ''}';
                    return DropdownMenuItem<String>(
                      value: code,
                      child: Text(label, style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setSheetState(() {
                        selectedCompCode = val;
                        final match = availableComps.firstWhere(
                          (c) => 'C${c.data()['compartmentNumber'] ?? c.id.replaceAll(RegExp(r'\D'), '')}' == val,
                        );
                        selectedCompDoc = match;
                        medName = match.data()['medicationName'] ?? '';
                        dosage = match.data()['dosage'] ?? '1 tablet';
                      });
                    }
                  },
                ),

                const SizedBox(height: 16),

                // Auto-populated Medication Details Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A36C).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF00A36C).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A36C).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.pill, color: Color(0xFF00A36C), size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              medName,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Dosage: $dosage · Slot $selectedCompCode',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF00A36C), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Frequency selection
                Text('Administration Frequency', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedFreq,
                  dropdownColor: cardBgColor,
                  style: TextStyle(color: primaryTextColor),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(LucideIcons.repeat, color: Color(0xFF00A36C)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'Once', child: Text('Once')),
                  ],
                  onChanged: (val) => setSheetState(() => selectedFreq = val!),
                ),

                const SizedBox(height: 16),

                // Scheduled Time Picker
                Text('Scheduled Time', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: selectedTime,
                    );
                    if (picked != null) setSheetState(() => selectedTime = picked);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded, color: Color(0xFF00A36C)),
                            const SizedBox(width: 12),
                            Text(
                              'Time: ${selectedTime.format(ctx)}',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryTextColor),
                            ),
                          ],
                        ),
                        Icon(Icons.arrow_drop_down_rounded, color: secondaryTextColor),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Confirm and Save Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A36C),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                      elevation: 0,
                    ),
                    onPressed: isSaving ? null : () async {
                      final uid = _uid;
                      if (uid == null) return;

                      // Step 3: Confirmation Summary Dialog
                      final confirmed = await showDialog<bool>(
                        context: ctx,
                        builder: (confirmCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          title: const Row(
                            children: [
                              Icon(LucideIcons.calendarCheck, color: Color(0xFF00A36C)),
                              SizedBox(width: 10),
                              Text('Confirm Schedule'),
                            ],
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Please review the schedule details before saving:'),
                              const SizedBox(height: 14),
                              _summaryRow('Medication', medName),
                              _summaryRow('Dosage', dosage),
                              _summaryRow('Compartment', selectedCompCode),
                              _summaryRow('Time', selectedTime.format(confirmCtx)),
                              _summaryRow('Frequency', selectedFreq),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(confirmCtx, false),
                              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00A36C),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => Navigator.pop(confirmCtx, true),
                              child: const Text('Confirm & Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );

                      if (confirmed != true) return;

                      setSheetState(() => isSaving = true);

                      final scheduledDateTime = DateTime(
                        _selectedDate.year,
                        _selectedDate.month,
                        _selectedDate.day,
                        selectedTime.hour,
                        selectedTime.minute,
                      );

                      final slotNum = selectedCompCode.replaceAll(RegExp(r'\D'), '');

                      final docData = <String, dynamic>{
                        'patientUid': uid,
                        'patientId': uid,
                        'medicationName': medName,
                        'dosage': dosage,
                        'compartment': 'Compartment $slotNum',
                        'compCode': selectedCompCode,
                        'scheduledTime': Timestamp.fromDate(scheduledDateTime),
                        'frequency': selectedFreq,
                        'status': 'Upcoming',
                        'isActive': true,
                        'updatedAt': FieldValue.serverTimestamp(),
                      };

                      try {
                        if (isEditing) {
                          await editDoc.reference.update(docData);
                        } else {
                          docData['createdAt'] = FieldValue.serverTimestamp();
                          await FirebaseFirestore.instance.collection('schedules').add(docData);
                        }

                        if (mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isEditing ? '$medName schedule updated!' : '$medName schedule created for $selectedCompCode!'),
                              backgroundColor: const Color(0xFF00A36C),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          );
                        }
                      } catch (e) {
                        setSheetState(() => isSaving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to save schedule: $e'),
                              backgroundColor: const Color(0xFFEF4444),
                            ),
                          );
                        }
                      }
                    },
                    child: isSaving
                        ? const SmartDoseLoading(size: 32, color: Colors.white)
                        : Text(
                            isEditing ? 'Update Schedule' : 'Save Schedule',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _deleteSchedule(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final medName = doc.data()?['medicationName'] ?? 'Medication';
    await doc.reference.delete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$medName schedule removed.'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }
  }

  void _showReadOnlyMedicationDetails(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final name = data['medicationName'] ?? 'Medication';
    final dosage = data['dosage'] ?? '';
    final comp = data['compartment'] ?? 'Compartment 1';
    final freq = data['frequency'] ?? 'Daily';
    final ts = data['scheduledTime'] as Timestamp?;
    final date = ts?.toDate();
    final timeStr = date != null ? DateFormat('hh:mm a').format(date) : '--:--';
    final cardBgColor = Theme.of(context).colorScheme.surface;
    final primaryTextColor = Theme.of(context).colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: primaryTextColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A36C).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.pill, color: Color(0xFF00A36C), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryTextColor)),
                      if (dosage.isNotEmpty)
                        Text(dosage, style: TextStyle(fontSize: 14, color: secondaryTextColor)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _summaryRow('Dispenser Slot', comp),
            _summaryRow('Scheduled Time', timeStr),
            _summaryRow('Frequency', freq),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  side: const BorderSide(color: Color(0xFF00A36C), width: 1.5),
                ),
                child: const Text('Close', style: TextStyle(color: Color(0xFF00A36C), fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Unified Pill Inventory: Refill & Compartment Configuration
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _refillCompartment(
      BuildContext context, int compNum, Map<String, dynamic> data, DocumentReference? ref) async {
    final name = data['medicationName'] ?? 'Medication in Slot C$compNum';
    final maxCapacity = data['maxCapacity'] as int? ?? 30;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.refresh_rounded, color: Color(0xFF00A36C)),
            SizedBox(width: 10),
            Text('Confirm Refill'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to refill Compartment C$compNum?'),
            const SizedBox(height: 12),
            _summaryRow('Compartment', 'Slot C$compNum'),
            _summaryRow('Medication', name),
            _summaryRow('Refill to', '$maxCapacity pills (Full Capacity)'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A36C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Refill', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final uid = _uid;
    if (uid == null) return;

    if (ref != null) {
      await ref.update({
        'stockCount': maxCapacity,
        'lastRefilledAt': FieldValue.serverTimestamp(),
      });
    } else {
      await FirebaseFirestore.instance.collection('compartments').doc('comp_$compNum').set({
        'compartmentNumber': compNum,
        'medicationName': name,
        'dosage': data['dosage'] ?? '1 tablet',
        'stockCount': maxCapacity,
        'maxCapacity': maxCapacity,
        'patientUid': uid,
        'lastRefilledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Compartment C$compNum ($name) refilled to $maxCapacity pills!'),
          backgroundColor: const Color(0xFF00A36C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }
  }

  Future<void> _showUpdateMedNameSheet(
      BuildContext context, int compNum, Map<String, dynamic> data, DocumentReference? ref) async {
    final nameCtrl = TextEditingController(text: data['medicationName'] ?? '');
    final doseCtrl = TextEditingController(text: data['dosage'] ?? '1 tablet');
    final stockCtrl = TextEditingController(text: (data['stockCount'] ?? 0).toString());
    final maxCtrl = TextEditingController(text: (data['maxCapacity'] ?? 30).toString());

    final theme = Theme.of(context);
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
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
                  Text(
                    'Configure Compartment C$compNum',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryTextColor),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Text(
                'Assign medication details and capacity for dispenser slot C$compNum',
                style: TextStyle(fontSize: 13, color: secondaryTextColor),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: nameCtrl,
                style: TextStyle(color: primaryTextColor),
                decoration: InputDecoration(
                  labelText: 'Medication Name',
                  hintText: 'e.g. Amoxicillin',
                  prefixIcon: const Icon(Icons.medication_outlined, color: Color(0xFF00A36C)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: doseCtrl,
                style: TextStyle(color: primaryTextColor),
                decoration: InputDecoration(
                  labelText: 'Dosage Details',
                  hintText: 'e.g. 500 mg, 1 tablet',
                  prefixIcon: const Icon(LucideIcons.pill, color: Color(0xFF00A36C)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: stockCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: primaryTextColor),
                      decoration: InputDecoration(
                        labelText: 'Current Stock',
                        prefixIcon: const Icon(Icons.inventory_rounded, color: Color(0xFF00A36C)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: maxCtrl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: primaryTextColor),
                      decoration: InputDecoration(
                        labelText: 'Max Capacity',
                        prefixIcon: const Icon(Icons.numbers_rounded, color: Color(0xFF00A36C)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
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
                    final newDose = doseCtrl.text.trim();
                    final stock = int.tryParse(stockCtrl.text.trim()) ?? 0;
                    final maxCap = int.tryParse(maxCtrl.text.trim()) ?? 30;

                    if (newName.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Medication name is required.')),
                      );
                      return;
                    }

                    // Confirmation Dialog Before Saving Important Inventory Changes
                    final confirmed = await showDialog<bool>(
                      context: ctx,
                      builder: (confirmCtx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        title: const Row(
                          children: [
                            Icon(Icons.check_circle_outline_rounded, color: Color(0xFF00A36C)),
                            SizedBox(width: 10),
                            Text('Confirm Assignment'),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Please confirm the compartment changes:'),
                            const SizedBox(height: 12),
                            _summaryRow('Compartment', 'Slot C$compNum'),
                            _summaryRow('Medication', newName),
                            _summaryRow('Dosage', newDose.isNotEmpty ? newDose : '1 dose'),
                            _summaryRow('Stock Count', '$stock / $maxCap pills'),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(confirmCtx, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00A36C),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () => Navigator.pop(confirmCtx, true),
                            child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );

                    if (confirmed != true) return;

                    final uid = _uid;
                    if (uid == null) return;

                    final updateMap = <String, dynamic>{
                      'compartmentNumber': compNum,
                      'medicationName': newName,
                      'dosage': newDose.isNotEmpty ? newDose : '1 tablet',
                      'stockCount': stock,
                      'maxCapacity': maxCap,
                      'patientUid': uid,
                      'updatedAt': FieldValue.serverTimestamp(),
                    };

                    if (ref != null) {
                      await ref.set(updateMap, SetOptions(merge: true));
                    } else {
                      await FirebaseFirestore.instance
                          .collection('compartments')
                          .doc('comp_$compNum')
                          .set(updateMap, SetOptions(merge: true));
                    }

                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Compartment C$compNum configured with $newName!'),
                          backgroundColor: const Color(0xFF00A36C),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      );
                    }
                  },
                  child: const Text('Save Compartment Details',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tab Selector: Visually Identical to History Tab (Today, Week, Month)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSectionSegmentedControl() {
    final theme = Theme.of(context);
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    final isSchedule = _selectedSection == 'schedule';
    final alignmentX = isSchedule ? -1.0 : 1.0;

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
          // Sliding Green Pill Background Indicator (identical to history_tab)
          AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            alignment: Alignment(alignmentX, 0.0),
            child: FractionallySizedBox(
              widthFactor: 0.5,
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

          // Options Row
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selectedSection = 'schedule'),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.calendarDays,
                          size: 16,
                          color: isSchedule ? Colors.white : secondaryTextColor,
                        ),
                        const SizedBox(width: 8),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 250),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                            color: isSchedule ? Colors.white : secondaryTextColor,
                          ),
                          child: const Text('Schedule'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selectedSection = 'inventory'),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.boxes,
                          size: 16,
                          color: !isSchedule ? Colors.white : secondaryTextColor,
                        ),
                        const SizedBox(width: 8),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 250),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                            color: !isSchedule ? Colors.white : secondaryTextColor,
                          ),
                          child: const Text('Pill Inventory'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pill Inventory Content (All 10 Compartments Displayed Consistently)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildInventoryContent() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _compartmentsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: SmartDoseLoading(size: 80)),
          );
        }

        final rawDocs = snapshot.data?.docs ?? [];
        _latestCompartmentDocs = rawDocs;

        // Map existing compartment docs by compartment number (1..10)
        final Map<int, QueryDocumentSnapshot<Map<String, dynamic>>> docMap = {};
        for (final doc in rawDocs) {
          final numVal = doc.data()['compartmentNumber'] as int? ??
              int.tryParse(doc.id.replaceAll(RegExp(r'\D'), ''));
          if (numVal != null && numVal >= 1 && numVal <= 10) {
            docMap[numVal] = doc;
          }
        }

        // Calculate summary across all 10 slots
        int occupiedCount = 0;
        int lowCount = 0;
        int emptyCount = 0;

        for (int i = 1; i <= 10; i++) {
          final doc = docMap[i];
          final data = doc?.data();
          final name = (data?['medicationName'] as String? ?? '').trim();
          final stock = (data?['stockCount'] as int? ?? 0);
          if (name.isNotEmpty) {
            occupiedCount++;
            if (stock == 0) {
              emptyCount++;
            } else if (stock <= 3) {
              lowCount++;
            }
          } else {
            emptyCount++;
          }
        }

        return Column(
          children: [
            _buildInventorySummaryHeader(10, occupiedCount, lowCount, emptyCount),
            const SizedBox(height: 16),
            ...List.generate(10, (idx) {
              final slotNum = idx + 1;
              final doc = docMap[slotNum];
              return _buildCompartmentSlotCard(slotNum, doc, isDark, cardBgColor, primaryTextColor, secondaryTextColor);
            }),
          ],
        );
      },
    );
  }

  Widget _buildCompartmentSlotCard(
    int slotNum,
    QueryDocumentSnapshot<Map<String, dynamic>>? doc,
    bool isDark,
    Color cardBgColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    final data = doc?.data() ?? <String, dynamic>{};
    final medName = (data['medicationName'] as String? ?? '').trim();
    final dosage = data['dosage'] as String? ?? '';
    final stock = data['stockCount'] as int? ?? 0;
    final maxCap = data['maxCapacity'] as int? ?? 30;
    final isAssigned = medName.isNotEmpty;

    final progress = maxCap > 0 ? (stock / maxCap).clamp(0.0, 1.0) : 0.0;
    final isLow = isAssigned && stock <= 3 && stock > 0;
    final isEmpty = isAssigned && stock == 0;
    final lastRefilled = data['lastRefilledAt'] as Timestamp?;
    final refilledStr = lastRefilled != null
        ? DateFormat('MMM d, hh:mm a').format(lastRefilled.toDate())
        : null;

    Color borderColor = isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB);
    Color barColor = const Color(0xFF00A36C);
    if (!isAssigned) {
      borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0);
    } else if (isEmpty) {
      borderColor = const Color(0xFFFCA5A5);
      barColor = const Color(0xFFEF4444);
    } else if (isLow) {
      borderColor = const Color(0xFFFBBF24);
      barColor = const Color(0xFFF59E0B);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: (isLow || isEmpty) ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
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
                      color: isAssigned ? const Color(0xFFE6F7F0) : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Comp $slotNum',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isAssigned ? const Color(0xFF00A36C) : secondaryTextColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAssigned ? medName : 'Empty / Unassigned',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isAssigned ? primaryTextColor : secondaryTextColor,
                        ),
                      ),
                      if (isAssigned && dosage.isNotEmpty)
                        Text(
                          dosage,
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                    ],
                  ),
                ],
              ),
              if (!isAssigned)
                _inventoryStatusBadge('Empty Slot', Colors.grey, Colors.grey.withValues(alpha: 0.15))
              else if (isEmpty)
                _inventoryStatusBadge('Empty', const Color(0xFFEF4444), const Color(0xFFFEE2E2))
              else if (isLow)
                _inventoryStatusBadge('Low Stock', const Color(0xFFD97706), const Color(0xFFFEF3C7))
              else
                _inventoryStatusBadge('Ready', const Color(0xFF10B981), const Color(0xFFD1FAE5)),
            ],
          ),
          const SizedBox(height: 14),

          // Progress indicator for stocked pills
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: isAssigned ? progress : 0.0,
                    minHeight: 10,
                    backgroundColor: isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                isAssigned ? '$stock / $maxCap pills' : '0 / $maxCap pills',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: primaryTextColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),

          if (refilledStr != null) ...[
            const SizedBox(height: 6),
            Text(
              'Last refilled: $refilledStr',
              style: TextStyle(fontSize: 11, color: secondaryTextColor),
            ),
          ],

          // Caregiver Editing Controls (Role-based permissions)
          if (widget.isCaregiver) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryTextColor,
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () => _showUpdateMedNameSheet(context, slotNum, data, doc?.reference),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: Text(isAssigned ? 'Edit Medication' : 'Assign Medication',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                if (isAssigned) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A36C),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    onPressed: () => _refillCompartment(context, slotNum, data, doc?.reference),
                    icon: const Icon(Icons.refresh_rounded, size: 15, color: Colors.white),
                    label: const Text('Refill',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInventorySummaryHeader(int total, int occupied, int lowCount, int emptyCount) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF00C882), Color(0xFF00A36C)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00A36C).withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _inventorySummaryItem('$total', 'Available Comps', Icons.grid_view_rounded),
          _inventorySummaryDivider(),
          _inventorySummaryItem('$occupied', 'Occupied', Icons.check_circle_rounded),
          _inventorySummaryDivider(),
          _inventorySummaryItem('$lowCount', 'Low Stock', Icons.warning_amber_rounded),
          _inventorySummaryDivider(),
          _inventorySummaryItem('$emptyCount', 'Empty Slots', Icons.remove_circle_outline_rounded),
        ],
      ),
    );
  }

  Widget _inventorySummaryItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _inventorySummaryDivider() {
    return Container(width: 1, height: 36, color: Colors.white24);
  }

  Widget _inventoryStatusBadge(String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Main Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    final content = Stack(
      children: [
        SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.isStandalone) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedSection == 'schedule' ? 'Schedule' : 'Pill Inventory',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: primaryTextColor,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedSection == 'schedule'
                              ? DateFormat('EEEE, d MMMM yyyy').format(_selectedDate)
                              : 'SmartDose 10-Compartment Dispenser',
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
                const SizedBox(height: 16),
              ],
              _buildSectionSegmentedControl(),
              const SizedBox(height: 20),
              if (_selectedSection == 'schedule') ...[
                _buildDateStrip(),
                const SizedBox(height: 24),
                _buildScheduleList(),
              ] else ...[
                _buildInventoryContent(),
              ],
            ],
          ),
        ),

        // Floating Action Button (Caregiver only on schedule section)
        if (widget.isCaregiver && _selectedSection == 'schedule')
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => _showMedicationSheet(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xFF00C882), Color(0xFF00A36C)],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00A36C).withValues(alpha: 0.38),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Schedule medication',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (widget.isStandalone) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            _selectedSection == 'schedule' ? 'Medication Schedule' : 'Pill Inventory',
            style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor),
          ),
          backgroundColor: theme.cardTheme.color ?? theme.colorScheme.surface,
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
            ),
          ],
        ),
        body: content,
      );
    }

    return content;
  }

  Widget _buildDateStrip() {
    const dayLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (index) {
        final date = _weekDays[index];
        final isSelected = index == _selectedDateIndex;
        final isToday = date.day == DateTime.now().day &&
            date.month == DateTime.now().month &&
            date.year == DateTime.now().year;

        return GestureDetector(
          onTap: () => setState(() => _selectedDateIndex = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF00A36C)
                  : (isToday ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFE6F7F0)) : cardBgColor),
              borderRadius: BorderRadius.circular(16),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF00A36C).withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              children: [
                Text(
                  dayLabels[index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : (isToday ? const Color(0xFF00A36C) : primaryTextColor.withValues(alpha: 0.6)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : primaryTextColor,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildScheduleList() {
    final theme = Theme.of(context);
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _schedulesStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: SmartDoseLoading(size: 80)),
          );
        }

        final allDocs = snapshot.data?.docs ?? [];
        final targetDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

        final docs = allDocs.where((doc) {
          final data = doc.data();
          if ((data['isActive'] ?? true) != true) return false;
          final ts = data['scheduledTime'] as Timestamp?;
          if (ts == null) return false;
          final schedDate = ts.toDate();
          final schedDay = DateTime(schedDate.year, schedDate.month, schedDate.day);

          if (targetDay.isBefore(schedDay)) return false;

          final freq = (data['frequency'] as String? ?? 'Daily').trim().toLowerCase();
          if (freq == 'daily') {
            return true;
          } else if (freq == 'weekly') {
            return targetDay.weekday == schedDay.weekday;
          } else {
            return targetDay.year == schedDay.year &&
                targetDay.month == schedDay.month &&
                targetDay.day == schedDay.day;
          }
        }).toList();

        docs.sort((a, b) {
          final tsA = a.data()['scheduledTime'] as Timestamp?;
          final tsB = b.data()['scheduledTime'] as Timestamp?;
          if (tsA == null || tsB == null) return 0;
          return tsA.compareTo(tsB);
        });

        if (docs.isEmpty) {
          return Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Icon(Icons.calendar_today_outlined, size: 48, color: secondaryTextColor.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text(
                  'No medications scheduled',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isCaregiver
                      ? 'Tap "Schedule medication" below to create a schedule from your Pill Inventory.'
                      : 'Your caregiver configures and manages your medication schedules.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: secondaryTextColor),
                ),
              ],
            ),
          );
        }

        return Column(
          children: docs.map((doc) => _buildScheduleCard(doc)).toList(),
        );
      },
    );
  }

  Widget _buildScheduleCard(DocumentSnapshot<Map<String, dynamic>> doc) {
    final med = doc.data() ?? {};
    final name = med['medicationName'] ?? 'Medication';
    final dosage = med['dosage'] ?? '500 mg';
    final comp = med['compCode'] ?? med['compartment'] ?? 'C1';
    final status = med['status'] as String? ?? 'Upcoming';
    final ts = med['scheduledTime'] as Timestamp?;
    final date = ts?.toDate();
    final timeNumStr = date != null ? DateFormat('hh:mm').format(date) : '--:--';
    final amPmStr = date != null ? DateFormat('a').format(date) : '';

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    Color statusBg;
    Color statusText;
    IconData statusIcon;

    switch (status.toLowerCase()) {
      case 'taken':
        statusBg = isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5);
        statusText = const Color(0xFF10B981);
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      case 'missed':
        statusBg = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2);
        statusText = const Color(0xFFEF4444);
        statusIcon = Icons.cancel_outlined;
        break;
      case 'late':
        statusBg = isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7);
        statusText = const Color(0xFFF59E0B);
        statusIcon = Icons.access_time_rounded;
        break;
      default:
        statusBg = isDark ? const Color(0xFF064E3B) : const Color(0xFFE6F7F0);
        statusText = const Color(0xFF00A36C);
        statusIcon = Icons.access_time_rounded;
    }

    return Dismissible(
      key: Key(doc.id),
      direction: widget.isCaregiver ? DismissDirection.endToStart : DismissDirection.none,
      background: Container(
        margin: const EdgeInsets.only(bottom: 14),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 28),
      ),
      confirmDismiss: (_) async {
        if (!widget.isCaregiver) return false;
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove medication?'),
            content: Text('Remove $name from this schedule?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Remove', style: TextStyle(color: Color(0xFFEF4444))),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => _deleteSchedule(doc),
      child: GestureDetector(
        onTap: () => widget.isCaregiver
            ? _showMedicationSheet(editDoc: doc)
            : _showReadOnlyMedicationDetails(doc),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardBgColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.5) : const Color(0xFFE6F7F0),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF00A36C).withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      timeNumStr,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00A36C),
                      ),
                    ),
                    Text(
                      amPmStr,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF00A36C),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$dosage · $comp',
                      style: TextStyle(
                        fontSize: 13,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(statusIcon, color: statusText, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: statusText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
