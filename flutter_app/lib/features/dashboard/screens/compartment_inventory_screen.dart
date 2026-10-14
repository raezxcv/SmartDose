import 'package:flutter/material.dart';
import 'meds_tab.dart';

class CompartmentInventoryScreen extends StatelessWidget {
  final bool isCaregiver;
  final String? patientUid;

  const CompartmentInventoryScreen({
    super.key,
    this.isCaregiver = false,
    this.patientUid,
  });

  @override
  Widget build(BuildContext context) {
    return PatientMedsTab(
      isCaregiver: isCaregiver,
      patientUid: patientUid,
      initialSection: 'inventory',
      isStandalone: true,
    );
  }
}
