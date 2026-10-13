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
  const PatientMedsTab({super.key, this.isCaregiver = false, this.patientUid});

  @override
  State<PatientMedsTab> createState() => _PatientMedsTabState();
}

class _PatientMedsTabState extends State<PatientMedsTab> {
  int _selectedDateIndex = 0;
  late List<DateTime> _weekDays;
  Timer? _countdownTimer;

  String? get _uid => widget.patientUid ?? FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _generateWeekDays();
    _startTimer();
  }

  void _startTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
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

  Stream<QuerySnapshot<Map<String, dynamic>>>? get _schedulesStream {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('schedules')
        .where('patientUid', isEqualTo: uid)
        .snapshots();
  }

  void _showMedicationSheet({DocumentSnapshot<Map<String, dynamic>>? editDoc}) {
    final isEditing = editDoc != null;
    final editData = editDoc?.data();

    final nameCtrl = TextEditingController(text: editData?['medicationName'] ?? '');

    String initialDosageNum = '';
    String selectedUnit = 'mg';
    if (isEditing && editData?['dosage'] != null) {
      final rawDosage = (editData!['dosage'] as String).trim();
      final parts = rawDosage.split(' ');
      if (parts.length >= 2) {
        initialDosageNum = parts.first;
        selectedUnit = parts.sublist(1).join(' ');
      } else {
        initialDosageNum = rawDosage;
      }
    }
    final dosageCtrl = TextEditingController(text: initialDosageNum);

    String selectedComp = editData?['compartment'] ?? 'Compartment 1';
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

    const availableUnits = ['tablet', 'pill', 'mg', 'ml', 'capsule', 'drop', 'g'];
    bool isSaving = false;
    String? nameError;
    String? dosageError;

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
                      isEditing ? 'Edit Medication' : 'Add Medication',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                    Row(
                      children: [
                        if (isEditing)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                            tooltip: 'Delete Medication',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: ctx,
                                builder: (dialogCtx) => AlertDialog(
                                  title: const Text('Delete Medication?'),
                                  content: Text('Are you sure you want to delete ${nameCtrl.text}? This action cannot be undone.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialogCtx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialogCtx, true),
                                      child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                final medName = nameCtrl.text.trim();
                                await editDoc.reference.delete();
                                if (mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('$medName deleted!'),
                                      backgroundColor: const Color(0xFFEF4444),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: primaryTextColor.withValues(alpha: 0.6)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: primaryTextColor),
                  onChanged: (_) {
                    if (nameError != null) {
                      setSheetState(() => nameError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Medication Name',
                    hintText: 'e.g. Metformin',
                    errorText: nameError,
                    prefixIcon: const Icon(Icons.medication_outlined, color: Color(0xFF00A36C)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 14),

                // Unified Single Input Box for Dosage & Unit
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Dosage',
                    errorText: dosageError,
                    prefixIcon: const Icon(Icons.fitness_center_rounded, color: Color(0xFF00A36C)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: dosageCtrl,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: primaryTextColor, fontSize: 16),
                          onChanged: (_) {
                            if (dosageError != null) {
                              setSheetState(() => dosageError = null);
                            }
                          },
                          decoration: const InputDecoration(
                            hintText: 'e.g. 500',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      Container(
                        height: 22,
                        width: 1,
                        color: Theme.of(context).dividerColor,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: availableUnits.contains(selectedUnit) ? selectedUnit : 'mg',
                          dropdownColor: cardBgColor,
                          isDense: true,
                          style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold, fontSize: 15),
                          icon: Icon(Icons.arrow_drop_down_rounded, color: primaryTextColor.withValues(alpha: 0.7)),
                          items: availableUnits
                              .map((u) => DropdownMenuItem(
                                    value: u,
                                    child: Text(u, style: TextStyle(color: primaryTextColor)),
                                  ))
                              .toList(),
                          onChanged: (val) => setSheetState(() => selectedUnit = val!),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedComp,
                        dropdownColor: cardBgColor,
                        style: TextStyle(color: primaryTextColor),
                        decoration: InputDecoration(
                          labelText: 'Compartment',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        items: List.generate(10, (i) => 'Compartment ${i + 1}')
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text('Comp ${c.split(' ').last}', style: TextStyle(color: primaryTextColor)),
                                ))
                            .toList(),
                        onChanged: (val) => setSheetState(() => selectedComp = val!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedFreq,
                        dropdownColor: cardBgColor,
                        style: TextStyle(color: primaryTextColor),
                        decoration: InputDecoration(
                          labelText: 'Frequency',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                          DropdownMenuItem(value: 'Once', child: Text('Once')),
                          DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
                        ],
                        onChanged: (val) => setSheetState(() => selectedFreq = val!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
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
                              'Scheduled: ${selectedTime.format(ctx)}',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: primaryTextColor),
                            ),
                          ],
                        ),
                        Icon(Icons.arrow_drop_down_rounded, color: primaryTextColor.withValues(alpha: 0.6)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A36C),
                      disabledBackgroundColor: const Color(0xFF00A36C),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                      elevation: 0,
                    ),
                    onPressed: isSaving ? null : () async {
                      final name = nameCtrl.text.trim();
                      final rawNum = dosageCtrl.text.trim();
                      final uid = _uid;

                      final hasNameErr = name.isEmpty;
                      final hasDosageErr = rawNum.isEmpty;

                      if (hasNameErr || hasDosageErr) {
                        setSheetState(() {
                          nameError = hasNameErr ? 'Medication name is required' : null;
                          dosageError = hasDosageErr ? 'Dosage quantity is required' : null;
                        });
                        return;
                      }

                      final dosageStr = '$rawNum $selectedUnit';

                      if (uid == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('User session expired. Please sign in again.'),
                            backgroundColor: Color(0xFFEF4444),
                          ),
                        );
                        return;
                      }

                      setSheetState(() => isSaving = true);

                      final compNum = selectedComp.split(' ').last;
                      final scheduledDateTime = DateTime(
                        _selectedDate.year,
                        _selectedDate.month,
                        _selectedDate.day,
                        selectedTime.hour,
                        selectedTime.minute,
                      );

                      final docData = <String, dynamic>{
                        'patientUid': uid,
                        'patientId': uid,
                        'medicationName': name,
                        'dosage': dosageStr,
                        'compartment': selectedComp,
                        'compCode': 'C$compNum',
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
                              content: Text(isEditing ? '$name updated!' : '$name added to $selectedComp!'),
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
                              content: Text('Failed to save medication: $e'),
                              backgroundColor: const Color(0xFFEF4444),
                            ),
                          );
                        }
                      }
                    },
                    child: isSaving
                        ? const SmartDoseLoading(size: 32, color: Colors.white)
                        : Text(
                            isEditing ? 'Update Medication' : 'Save Medication',
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

  Future<void> _deleteSchedule(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final medName = doc.data()?['medicationName'] ?? 'Medication';
    await doc.reference.delete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$medName deleted.'),
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
                      const SizedBox(height: 2),
                      Text(dosage, style: TextStyle(fontSize: 14, color: secondaryTextColor, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A36C).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(comp, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00A36C))),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF1E1E22)
                    : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF27272A)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Scheduled Time', style: TextStyle(color: secondaryTextColor, fontSize: 13, fontWeight: FontWeight.w500)),
                      Text(timeStr, style: TextStyle(color: primaryTextColor, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Frequency', style: TextStyle(color: secondaryTextColor, fontSize: 13, fontWeight: FontWeight.w500)),
                      Text(freq, style: TextStyle(color: primaryTextColor, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Permissions', style: TextStyle(color: secondaryTextColor, fontSize: 13, fontWeight: FontWeight.w500)),
                      const Text('Managed by Caregiver (View-only)', style: TextStyle(color: Color(0xFF00A36C), fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    return Stack(
      children: [
        SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
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
                        'Schedule',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: primaryTextColor, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEEE, d MMMM yyyy').format(_selectedDate),
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
              _buildDateStrip(),
              const SizedBox(height: 24),
              _buildScheduleList(),
            ],
          ),
        ),

        // Floating Action Button (Caregiver only)
        if (widget.isCaregiver)
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
                      'Add medication',
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
  }

  Widget _buildDateStrip() {
    const dayLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = theme.cardTheme.color ?? theme.colorScheme.surface;
    final primaryTextColor = theme.colorScheme.onSurface;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.65);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_weekDays.length, (idx) {
          final date = _weekDays[idx];
          final isSelected = idx == _selectedDateIndex;

          return GestureDetector(
            onTap: () => setState(() => _selectedDateIndex = idx),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF00C882), Color(0xFF00A36C)],
                      )
                    : null,
                borderRadius: BorderRadius.circular(28),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF00A36C).withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dayLabels[idx],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: isSelected ? Colors.white : primaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
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
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: SmartDoseLoading(size: 140));
        }

        final allDocs = snapshot.data?.docs ?? [];
        final targetDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

        final docs = allDocs.where((doc) {
          final data = doc.data();
          final isActive = data['isActive'] ?? true;
          if (!isActive) return false;
          final ts = data['scheduledTime'] as Timestamp?;
          if (ts == null) return false;
          final schedDate = ts.toDate();
          final schedDay = DateTime(schedDate.year, schedDate.month, schedDate.day);

          // Cannot show medication on dates before its scheduled start date
          if (targetDay.isBefore(schedDay)) return false;

          final freq = (data['frequency'] as String? ?? 'Daily').trim().toLowerCase();
          if (freq == 'daily') {
            return true;
          } else if (freq == 'weekly') {
            return targetDay.weekday == schedDay.weekday;
          } else {
            // 'once' or single dose: must match exact same day
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
                      ? 'Tap "Add medication" below to schedule a dose for this day.'
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
    final comp = med['compartment'] ?? 'Compartment 1';
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

    String statusLabel = status;
    if (status.toLowerCase() == 'upcoming') {
      final occurrenceDate = date != null
          ? DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, date.hour, date.minute)
          : null;
      if (occurrenceDate != null) {
        final now = DateTime.now();
        final diff = occurrenceDate.difference(now);
        if (diff.isNegative) {
          if (now.difference(occurrenceDate).inHours >= 2) {
            statusLabel = 'Missed';
            statusBg = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2);
            statusText = const Color(0xFFEF4444);
            statusIcon = Icons.cancel_outlined;
          } else {
            statusLabel = 'Due now';
            statusBg = isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7);
            statusText = const Color(0xFFF59E0B);
            statusIcon = Icons.access_time_rounded;
          }
        } else {
          final h = diff.inHours;
          final m = diff.inMinutes % 60;
          final s = diff.inSeconds % 60;
          if (h > 0) {
            statusLabel = 'In ${h}h ${m}m';
          } else if (m > 0) {
            statusLabel = 'In ${m}m ${s}s';
          } else {
            statusLabel = 'In ${s}s';
          }
        }
      }
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
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF00A36C),
                        letterSpacing: -0.3,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      amPmStr,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF00A36C),
                        height: 1.1,
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
                    Text(name,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor)),
                    const SizedBox(height: 3),
                    Text('$dosage · $comp',
                        style: TextStyle(fontSize: 13, color: secondaryTextColor)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, color: statusText, size: 14),
                          const SizedBox(width: 4),
                          Text(statusLabel,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusText)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.isCaregiver)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 22),
                  tooltip: 'Delete Medication',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Medication?'),
                        content: Text('Are you sure you want to delete $name?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete', style: TextStyle(color: Color(0xFFEF4444))),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      _deleteSchedule(doc);
                    }
                  },
                ),
              Icon(Icons.chevron_right_rounded, color: secondaryTextColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
