import 'package:flutter/material.dart';
import 'linked_account_screen.dart';

/// ConnectedCaregiversScreen points to the unified LinkedAccountScreen
/// preserving backward compatibility for role-based patient and caregiver pairing.
class ConnectedCaregiversScreen extends StatelessWidget {
  const ConnectedCaregiversScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LinkedAccountScreen(isCaregiver: false);
  }
}
