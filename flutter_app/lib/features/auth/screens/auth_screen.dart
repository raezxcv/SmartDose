import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/auth_service.dart';
import 'package:smartdose/shared/widgets/smartdose_loading.dart';

/// AuthScreen — Primary Login screen with slightly darker rich emerald gradient background,
/// tight logo-to-title spacing via Transform.translate, higher Welcome Back position,
/// 44px spacing between subtitle block and Email field, KeyRound button, and "Create an account" link.
class AuthScreen extends StatefulWidget {
  final Function(String role, String name) onLoginSuccess;
  final VoidCallback onGoToSignUp;
  final VoidCallback onBack;

  const AuthScreen({
    super.key,
    required this.onLoginSuccess,
    required this.onGoToSignUp,
    required this.onBack,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  String? _errorMessage;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  late AnimationController _ctrl;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late Animation<double> _fieldsFade;
  late Animation<Offset> _fieldsSlide;
  late Animation<double> _btnFade;
  late Animation<Offset> _btnSlide;
  late Animation<double> _socialFade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850));

    _headerFade = _iv(0.0, 0.40);
    _headerSlide = _sv(0.0, 0.45);
    _fieldsFade = _iv(0.20, 0.60);
    _fieldsSlide = _sv(0.20, 0.65);
    _btnFade = _iv(0.45, 0.80);
    _btnSlide = _sv(0.45, 0.85);
    _socialFade = _iv(0.60, 1.0);

    _ctrl.forward();
  }

  Animation<double> _iv(double b, double e) => CurvedAnimation(
      parent: _ctrl, curve: Interval(b, e, curve: Curves.easeOut));

  Animation<Offset> _sv(double b, double e) =>
      Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(
              parent: _ctrl,
              curve: Interval(b, e, curve: Curves.easeOutCubic)));

  @override
  void dispose() {
    _ctrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final userData = await _authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (userData != null) {
        // Read role from the stored Firestore profile — never overwrite it at login.
        final role = (userData['role'] as String?)?.trim().toLowerCase() ?? 'patient';
        final name = (userData['name'] as String?) ?? 'User';
        widget.onLoginSuccess(role, name);
      } else {
        setState(() => _errorMessage = 'User record not found.');
      }
    } catch (e) {
      final msg = e.toString();
      setState(() => _errorMessage = msg.startsWith('Exception: ') ? msg.substring(11) : msg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPassword() {
    final emailCtrl = TextEditingController(text: _emailController.text);
    bool isSending = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top Icon Badge
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00A36C).withValues(alpha: 0.3), width: 1.5),
                  ),
                  child: const Icon(
                    LucideIcons.keyRound,
                    color: Color(0xFF00A36C),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Reset Password',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F2937),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Enter your registered email address below and we'll send you a link to reset your password.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                // Email input field
                const Align(
                  alignment: Alignment.centerLeft,
                  child: _FieldLabel(
                    icon: Icons.email_rounded,
                    label: 'EMAIL ADDRESS',
                    required: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Color(0xFF1F2937), fontSize: 15, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 15, fontWeight: FontWeight.w500),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: Color(0xFF00A36C), width: 2)),
                  ),
                ),
                const SizedBox(height: 24),
                // Buttons Row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                        ),
                        child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF00C882), Color(0xFF00A36C)]),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [BoxShadow(color: const Color(0xFF00A36C).withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: isSending
                                ? null
                                : () async {
                                    final text = emailCtrl.text.trim();
                                    if (text.contains('@')) {
                                      setDialogState(() => isSending = true);
                                      await _authService.sendPasswordReset(text);
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Password reset link sent! Check your inbox.'),
                                            backgroundColor: Color(0xFF00A36C),
                                          ),
                                        );
                                      }
                                    }
                                  },
                            borderRadius: BorderRadius.circular(25),
                            child: Center(
                              child: isSending
                                  ? const SmartDoseLoading(size: 32, color: Colors.white)
                                  : const Text('Send Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : const Color(0xFF005837),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF064E3B),
                    Color(0xFF18181B),
                    Color(0xFF121214),
                    Color(0xFF121214),
                  ],
                  stops: [0.0, 0.35, 0.70, 1.0],
                )
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF005837),
                    Color(0xFF00754C),
                    Color(0xFF00905D),
                    Color(0xFF00A86E),
                  ],
                  stops: [0.0, 0.35, 0.70, 1.0],
                ),
        ),
        child: Stack(
          children: [
            // ── Background circles with centered icons ─────────────────────
            // Sparkles — top-right large circle
            Positioned(
              top: -20, right: -20,
              child: Container(
                width: 140, height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                child: Center(
                  child: Icon(
                    LucideIcons.sparkles,
                    size: 28,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            // ShieldCheck — left mid circle
            Positioned(
              top: 60, left: -30,
              child: Container(
                width: 130, height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: Center(
                  child: Icon(
                    LucideIcons.shieldCheck,
                    size: 32,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            // Pill — standalone smaller circle, right side
            Positioned(
              top: 170, right: 10,
              child: Container(
                width: 110, height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
                child: Center(
                  child: Icon(
                    LucideIcons.pill,
                    size: 24,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),

            // ── Main Content Column ─────────────────────────────────────────
            Column(
              children: [
                // ── Top Hero Section (Compact Padding to Position Card Higher) ─
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                    child: Center(
                      child: FadeTransition(
                        opacity: _headerFade,
                        child: SlideTransition(
                          position: _headerSlide,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Transparent Logo
                              SizedBox(
                                width: 100,
                                height: 100,
                                child: Image.asset(
                                  'assets/Smart Dose Logo No Bg.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              // App Name sitting tightly below logo without gap
                              Transform.translate(
                                offset: const Offset(0, -16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'SmartDose',
                                      style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Your smart medication companion',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.94),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // ── Bottom Overlapping White Card Sheet (Welcome Back Higher) ──
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? Colors.black.withValues(alpha: 0.4) : Colors.black12,
                          blurRadius: 24,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // 1. Header Title & Subtitle — Higher Up
                                      FadeTransition(
                                        opacity: _headerFade,
                                        child: SlideTransition(
                                          position: _headerSlide,
                                          child: SizedBox(
                                            width: double.infinity,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                Text(
                                                  'Welcome back',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 30,
                                                    fontWeight: FontWeight.w700,
                                                    color: isDark ? Colors.white : const Color(0xFF1F2937),
                                                    letterSpacing: -0.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  'Enter your credentials below to log back into your account.',
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
                                      ),

                                      const SizedBox(height: 20),

                                      // Error Banner if present
                                      if (_errorMessage != null) ...[
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          margin: const EdgeInsets.only(bottom: 20),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFEE2E2),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: const Color(0xFFEF4444)),
                                          ),
                                          child: Row(children: [
                                            const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 20),
                                            const SizedBox(width: 10),
                                            Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13, fontWeight: FontWeight.w700))),
                                          ]),
                                        ),
                                      ],

                                      // 2. Input Fields — Centered
                                      FadeTransition(
                                        opacity: _fieldsFade,
                                        child: SlideTransition(
                                          position: _fieldsSlide,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const _FieldLabel(
                                                icon: Icons.email_rounded,
                                                label: 'EMAIL ADDRESS',
                                                required: true,
                                              ),
                                              const SizedBox(height: 8),
                                              TextFormField(
                                                controller: _emailController,
                                                keyboardType: TextInputType.emailAddress,
                                                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1F2937), fontSize: 16, fontWeight: FontWeight.w700),
                                                decoration: _pill('you@example.com'),
                                                validator: (v) => v == null || !v.contains('@') ? 'Enter a valid email' : null,
                                              ),

                                              const SizedBox(height: 18),

                                              const _FieldLabel(
                                                icon: Icons.lock_rounded,
                                                label: 'PASSWORD',
                                                required: true,
                                              ),
                                              const SizedBox(height: 8),
                                              TextFormField(
                                                controller: _passwordController,
                                                obscureText: _obscurePassword,
                                                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1F2937), fontSize: 16, fontWeight: FontWeight.w700),
                                                decoration: _pill('••••••••').copyWith(
                                                  suffixIcon: IconButton(
                                                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280), size: 22),
                                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                                  ),
                                                ),
                                                validator: (v) => v == null || v.length < 6 ? 'Password must be at least 6 characters' : null,
                                              ),

                                              const SizedBox(height: 14),

                                              Row(
                                                children: [
                                                  GestureDetector(
                                                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                                                    child: Row(children: [
                                                      Container(
                                                        width: 22, height: 22,
                                                        decoration: BoxDecoration(
                                                          color: _rememberMe ? const Color(0xFF00A36C) : (isDark ? const Color(0xFF121214) : Colors.white),
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: _rememberMe ? const Color(0xFF00A36C) : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFD1D5DB)), width: 1.5),
                                                        ),
                                                        child: _rememberMe ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text('Remember me', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF374151))),
                                                    ]),
                                                  ),
                                                  const Spacer(),
                                                  GestureDetector(
                                                    onTap: _showForgotPassword,
                                                    child: const Text('Forgot password?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF00A36C))),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      const SizedBox(height: 28),

                                      // 3. Log in Button
                                      FadeTransition(
                                        opacity: _btnFade,
                                        child: SlideTransition(
                                          position: _btnSlide,
                                          child: _GradientButton(
                                            text: 'Log in',
                                            icon: LucideIcons.keyRound,
                                            isLoading: _isLoading,
                                            onPressed: _signIn,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(height: 24),

                                      // 4. Centered "Don't have an account? Create an account" Link
                                      FadeTransition(
                                        opacity: _socialFade,
                                        child: Center(
                                          child: GestureDetector(
                                            onTap: widget.onGoToSignUp,
                                            child: RichText(
                                              textAlign: TextAlign.center,
                                              text: TextSpan(
                                                text: "Don't have an account? ",
                                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280)),
                                                children: const [TextSpan(text: 'Create an account', style: TextStyle(color: Color(0xFF00A36C), fontWeight: FontWeight.w900))],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _pill(String hint) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
          color: isDark ? const Color(0xFF71717A) : const Color(0xFF9CA3AF),
          fontSize: 15,
          fontWeight: FontWeight.w500),
      filled: true,
      fillColor: isDark ? const Color(0xFF121214) : const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: Color(0xFF00A36C), width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: Color(0xFFEF4444))),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2)),
    );
  }
}

// ─── Gradient Button ──────────────────────────────────────────────────────────

class _GradientButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _GradientButton({required this.text, this.icon, required this.onPressed, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFF00C882), Color(0xFF00A36C)]),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: const Color(0xFF00A36C).withValues(alpha: 0.38), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(28),
          child: Center(
            child: isLoading
                ? const SmartDoseLoading(size: 40, color: Colors.white)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                      ],
                      Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool required;

  const _FieldLabel({
    required this.icon,
    required this.label,
    required this.required,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF00A36C)),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
            letterSpacing: 0.8,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 3),
          const Text(
            '*',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Color(0xFFEF4444),
            ),
          ),
        ],
      ],
    );
  }
}
