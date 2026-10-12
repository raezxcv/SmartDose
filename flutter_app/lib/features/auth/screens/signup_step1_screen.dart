import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Signup Step 1 of 3 — "Choose your role"
/// Allows user to select between 'patient' and 'caregiver'.
class SignupStep1Screen extends StatefulWidget {
  final String initialRole;
  final VoidCallback onBack;
  final Function(String role) onNext;
  final void Function(VoidCallback) onRegisterSubmit;

  const SignupStep1Screen({
    super.key,
    this.initialRole = 'patient',
    required this.onBack,
    required this.onNext,
    required this.onRegisterSubmit,
  });

  @override
  State<SignupStep1Screen> createState() => _SignupStep1ScreenState();
}

class _SignupStep1ScreenState extends State<SignupStep1Screen>
    with SingleTickerProviderStateMixin {
  late String _selectedRole;

  late AnimationController _ctrl;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late Animation<double> _card1Fade;
  late Animation<Offset> _card1Slide;
  late Animation<double> _card2Fade;
  late Animation<Offset> _card2Slide;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.initialRole;
    widget.onRegisterSubmit(() => widget.onNext(_selectedRole));

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    Animation<double> iv(double b, double e) => CurvedAnimation(
        parent: _ctrl, curve: Interval(b, e, curve: Curves.easeOut));
    Animation<Offset> sv(double b, double e) =>
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _ctrl,
                curve: Interval(b, e, curve: Curves.easeOutCubic)));

    _headerFade = iv(0.00, 0.38);
    _headerSlide = sv(0.00, 0.42);
    _card1Fade = iv(0.18, 0.55);
    _card1Slide = sv(0.18, 0.58);
    _card2Fade = iv(0.34, 0.70);
    _card2Slide = sv(0.34, 0.73);

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Header Title & Subtitle
                  FadeTransition(
                    opacity: _headerFade,
                    child: SlideTransition(
                      position: _headerSlide,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Choose your role',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF1F2937),
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Select how you will be using SmartDose to customize your experience.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // 2. Patient Role Card
                  FadeTransition(
                    opacity: _card1Fade,
                    child: SlideTransition(
                      position: _card1Slide,
                      child: _RoleCard(
                        title: 'Patient',
                        subtitle:
                            'I am taking medications. View daily schedules, receive reminders, and request emergency dispense.',
                        icon: LucideIcons.user,
                        isSelected: _selectedRole == 'patient',
                        onTap: () {
                          setState(() => _selectedRole = 'patient');
                          widget.onRegisterSubmit(() => widget.onNext('patient'));
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. Caregiver Role Card
                  FadeTransition(
                    opacity: _card2Fade,
                    child: SlideTransition(
                      position: _card2Slide,
                      child: _RoleCard(
                        title: 'Caregiver / Family',
                        subtitle:
                            'I configure and manage medication schedules, compartment assignments, refills, and emergency contacts.',
                        icon: LucideIcons.heartHandshake,
                        isSelected: _selectedRole == 'caregiver',
                        onTap: () {
                          setState(() => _selectedRole = 'caregiver');
                          widget.onRegisterSubmit(() => widget.onNext('caregiver'));
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.35) : const Color(0xFFF0FDF4))
              : (isDark ? const Color(0xFF1E1E22) : const Color(0xFFF9FAFB)),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00A36C)
                : (isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB)),
            width: isSelected ? 2.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFF00A36C).withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00A36C)
                    : (isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB)),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? Colors.white
                    : (isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280)),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? const Color(0xFF00A36C)
                              : (isDark ? Colors.white : const Color(0xFF1F2937)),
                        ),
                      ),
                      const Spacer(),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF00A36C) : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF00A36C)
                                : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB)),
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                    ),
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
