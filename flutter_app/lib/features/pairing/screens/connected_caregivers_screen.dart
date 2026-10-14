import 'package:flutter/material.dart';
import 'linked_account_screen.dart';

/// ConnectedCaregiversScreen now points to the unified LinkedAccountScreen
/// preserving backward compatibility while strictly enforcing 1-to-1 pairing.
class ConnectedCaregiversScreen extends StatelessWidget {
  const ConnectedCaregiversScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LinkedAccountScreen(isCaregiver: false);
  }
}
