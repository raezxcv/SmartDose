import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/auth_screen.dart';
import 'features/auth/screens/signup_step1_screen.dart';
import 'features/auth/screens/signup_step2_screen.dart';
import 'features/auth/screens/signup_step3_screen.dart';
import 'features/auth/providers/auth_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/dashboard/screens/caregiver_dashboard_screen.dart';
import 'shared/widgets/smartdose_loading.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: SmartDoseApp()));
}
// ── Route helpers ─────────────────────────────────────────────────────────────



/// Fade — used for top-level auth transitions (splash, auth choice, login, dashboard)
Route<T> _fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: const Duration(milliseconds: 380),
    transitionsBuilder: (_, anim, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeIn),
      child: child,
    ),
  );
}

// ── App ───────────────────────────────────────────────────────────────────────

class SmartDoseApp extends ConsumerWidget {
  const SmartDoseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'SmartDose',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      themeAnimationDuration: const Duration(milliseconds: 400),
      themeAnimationCurve: Curves.easeInOut,
      builder: (context, child) {
        return DefaultTextStyle(
          style: TextStyle(
            fontFamily: AppTheme.fontFamilyName,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          child: child!,
        );
      },
      home: const _RootNavigator(),
    );
  }
}

// ── Root Navigator ────────────────────────────────────────────────────────────

class _RootNavigator extends StatefulWidget {
  const _RootNavigator();
  @override
  State<_RootNavigator> createState() => _RootNavigatorState();
}

class _RootNavigatorState extends State<_RootNavigator> {
  final _navKey = GlobalKey<NavigatorState>();
  final _auth = AuthService();

  NavigatorState get _nav => _navKey.currentState!;

  // ── Routing helpers ───────────────────────────────────────────────────────

  void _pushDashboard(String role, String name) {
    final Widget dashboard = (role == 'caregiver')
        ? CaregiverHomeScreen(userName: name, onSignOut: _signOut)
        : PatientHomeScreen(userName: name, onSignOut: _signOut);
    _nav.pushAndRemoveUntil(_fadeRoute(dashboard), (_) => false);
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    _nav.pushAndRemoveUntil(_fadeRoute(_buildLogin()), (_) => false);
  }

  /// Persistent Auth Check: Automatically skip login if user has an active session
  Future<void> _checkInitialAuthSession() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      try {
        final profile = await _auth.getUserProfile(currentUser.uid);
        final name = profile?['name'] ?? currentUser.displayName ?? 'User';
        final role = profile?['role'] ?? 'patient';
        _pushDashboard(role, name);
        return;
      } catch (e) {
        debugPrint('Error checking auth session: $e');
      }
    }
    _nav.pushReplacement(_fadeRoute(_buildLogin()));
  }

  // ── Screen builders ───────────────────────────────────────────────────────


  Widget _buildLogin({Key? key}) => AuthScreen(
        key: key,
        onLoginSuccess: _pushDashboard,
        onGoToSignUp: () => _nav.push(
          _fadeRoute(_SignupFlow(
            onSuccess: _pushDashboard,
            onGoToLogin: () {
              _nav.pushAndRemoveUntil(
                _fadeRoute(_buildLogin(key: UniqueKey())),
                (_) => false,
              );
            },
          )),
        ),
        onBack: () => _nav.pop(),
      );


  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler(
      onPopWithResult: (_) {
        if (_navKey.currentState?.canPop() ?? false) {
          _navKey.currentState?.pop();
        }
      },
      child: Navigator(
        key: _navKey,
        onGenerateInitialRoutes: (_, __) => [
          MaterialPageRoute(
            builder: (_) => SplashScreen(
              onFinish: _checkInitialAuthSession,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Self-contained 3-step Signup Flow ────────────────────────────────────────
// Uses a custom sliding page switcher so that BOTH the outgoing and incoming
// pages animate simultaneously (old exits left, new enters from right).
// The floating top bar stays completely fixed.

class _SignupFlow extends StatefulWidget {
  final void Function(String role, String name) onSuccess;
  final VoidCallback? onGoToLogin;

  const _SignupFlow({
    required this.onSuccess,
    this.onGoToLogin,
  });

  @override
  State<_SignupFlow> createState() => _SignupFlowState();
}

class _SignupFlowState extends State<_SignupFlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<Offset> _incomingSlide;
  late Animation<Offset> _outgoingSlide;

  int _currentStep = 1;
  bool _isForward = true;
  bool _isAnimating = false;
  bool _isCreating = false;
  bool _isStepLoading = false;

  // Submit handler registered by the active step
  VoidCallback? _stepSubmit;

  // We keep both old and new page widgets to cross-animate them
  late Widget _currentPage;
  Widget? _previousPage;

  // Signup draft
  String _role = 'patient';
  String _name = '';
  String _phone = '';
  String? _dob;
  String? _gender;
  String? _address;
  String _email = '';
  String _password = '';
  String _confirmPassword = '';

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isAnimating = false;
          _previousPage = null;
        });
      }
    });

    _buildTweens();
    _currentPage = _buildStep1();
  }

  void _buildTweens() {
    const curve = Curves.easeInOutCubic;
    if (_isForward) {
      _incomingSlide =
          Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .animate(CurvedAnimation(parent: _slideCtrl, curve: curve));
      _outgoingSlide =
          Tween(begin: Offset.zero, end: const Offset(-1.0, 0.0))
              .animate(CurvedAnimation(parent: _slideCtrl, curve: curve));
    } else {
      _incomingSlide =
          Tween(begin: const Offset(-1.0, 0.0), end: Offset.zero)
              .animate(CurvedAnimation(parent: _slideCtrl, curve: curve));
      _outgoingSlide =
          Tween(begin: Offset.zero, end: const Offset(1.0, 0.0))
              .animate(CurvedAnimation(parent: _slideCtrl, curve: curve));
    }
  }

  void _animateToPage(Widget newPage, {required bool forward}) {
    if (_isAnimating) return;
    setState(() {
      _isForward = forward;
      _buildTweens();
      _previousPage = _currentPage;
      _currentPage = newPage;
      _isAnimating = true;
      _stepSubmit = null;
    });
    _slideCtrl.forward(from: 0.0);
  }

  // Called by each step on initState to register its submit handler
  void _registerSubmit(VoidCallback fn) {
    // Use post-frame so it doesn't conflict with build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _stepSubmit = fn);
    });
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  // ── Step callbacks ─────────────────────────────────────────────────────────

  void _onStep1Done(String role) {
    _role = role;
    _currentStep = 2;
    _animateToPage(_buildStep2(), forward: true);
  }

  void _onStep2Done(
      String name, String phone, String? dob, String? gender, String? address) {
    _name = name;
    _phone = phone;
    _dob = dob;
    _gender = gender;
    _address = address;
    _currentStep = 3;
    _animateToPage(_buildStep3(), forward: true);
  }

  void _handleBack() {
    if (_isAnimating || _isCreating) return;
    if (_currentStep == 3) {
      _currentStep = 2;
      _animateToPage(_buildStep2(), forward: false);
    } else if (_currentStep == 2) {
      _currentStep = 1;
      _animateToPage(_buildStep1(), forward: false);
    } else {
      if (widget.onGoToLogin != null) {
        widget.onGoToLogin!();
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  void _handleGoToLogin() {
    if (widget.onGoToLogin != null) {
      widget.onGoToLogin!();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _onSignupSuccess(String role, String name) {
    setState(() {
      _isCreating = false;
      _isStepLoading = false;
      _currentStep = 4;
    });
    _animateToPage(_buildSuccessScreen(role, name), forward: true);
  }

  void _onCreatingChanged(bool creating) {
    if (mounted) {
      setState(() {
        _isCreating = creating;
        _isStepLoading = creating;
      });
    }
  }

  // ── Page builders ──────────────────────────────────────────────────────────

  Widget _buildStep1() => SignupStep1Screen(
        key: const ValueKey('step1'),
        initialRole: _role,
        onBack: _handleBack,
        onNext: _onStep1Done,
        onRegisterSubmit: _registerSubmit,
      );

  Widget _buildStep2() => SignupStep2Screen(
        key: const ValueKey('step2'),
        initialName: _name,
        initialPhone: _phone,
        initialDob: _dob,
        initialGender: _gender,
        initialAddress: _address,
        onBack: _handleBack,
        onNext: _onStep2Done,
        onRegisterSubmit: _registerSubmit,
      );

  Widget _buildStep3() => SignupStep3Screen(
        key: const ValueKey('step3'),
        role: _role,
        name: _name,
        phone: _phone,
        dob: _dob,
        gender: _gender,
        address: _address,
        initialEmail: _email,
        initialPassword: _password,
        initialConfirmPassword: _confirmPassword,
        onDraftChanged: (email, password, confirmPassword) {
          _email = email;
          _password = password;
          _confirmPassword = confirmPassword;
        },
        googleUid: null,
        profilePhotoUrl: null,
        onBack: _handleBack,
        onSignupSuccess: _onSignupSuccess,
        onCreatingChanged: _onCreatingChanged,
        onRegisterSubmit: _registerSubmit,
      );

  Widget _buildSuccessScreen(String role, String name) =>
      _SignupSuccessScreen(
        key: const ValueKey('success'),
        name: name,
        onContinue: () => widget.onSuccess(role, name),
        onGoToLogin: widget.onGoToLogin,
      );

  @override
  Widget build(BuildContext context) {
    final bool showSteps = _currentStep <= 3;
    final int step = _currentStep.clamp(1, 3);
    final bool isLastStep = _currentStep == 3;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: _currentStep <= 1 && !_isCreating,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
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

                // ── Main Content Layout ────────────────────────────────────
                Column(
                  children: [
                    // Compact Hero (smaller = more card space)
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 80,
                                height: 80,
                                child: Image.asset(
                                  'assets/Smart Dose Logo No Bg.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              Transform.translate(
                                offset: const Offset(0, -8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'SmartDose',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      'Your smart medication companion',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.90),
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

                    const SizedBox(height: 8),

                    // White Card — taller
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(36),
                          ),
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
                          child: Column(
                            children: [
                              // ── Numbered Step Indicator (fixed, never scrolls)
                              if (showSteps)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(32, 22, 32, 0),
                                  child: _StepIndicator(currentStep: step),
                                ),

                              // ── Scrollable step content ───────────────────
                              Expanded(
                                child: ClipRect(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (_previousPage != null)
                                        SlideTransition(
                                          position: _outgoingSlide,
                                          child: _previousPage!,
                                        ),
                                      _isAnimating
                                          ? SlideTransition(
                                              position: _incomingSlide,
                                              child: _currentPage,
                                            )
                                          : _currentPage,
                                    ],
                                  ),
                                ),
                              ),

                              // ── Fixed Bottom Action Bar ──────────────────
                              if (_currentStep <= 3)
                                Container(
                                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: isDark
                                            ? Colors.black.withValues(alpha: 0.25)
                                            : Colors.black.withValues(alpha: 0.06),
                                        blurRadius: 12,
                                        offset: const Offset(0, -4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          // Back button (steps 2 & 3 only)
                                          if (_currentStep >= 2) ...[
                                            GestureDetector(
                                              onTap: (_isCreating || _isAnimating) ? null : _handleBack,
                                              child: AnimatedOpacity(
                                                duration: const Duration(milliseconds: 200),
                                                opacity: (_isCreating || _isAnimating) ? 0.35 : 1.0,
                                                child: Container(
                                                  width: 52,
                                                  height: 52,
                                                  decoration: BoxDecoration(
                                                    color: isDark
                                                        ? const Color(0xFF27272A)
                                                        : const Color(0xFFF3F4F6),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: isDark
                                                          ? const Color(0xFF3F3F46)
                                                          : const Color(0xFFE5E7EB),
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    Icons.chevron_left_rounded,
                                                    color: isDark ? Colors.white : const Color(0xFF374151),
                                                    size: 28,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                          ],

                                          // Continue / Create Account button
                                          Expanded(
                                            child: Container(
                                              height: 52,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [Color(0xFF00C882), Color(0xFF00A36C)],
                                                ),
                                                borderRadius: BorderRadius.circular(26),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(0xFF00A36C).withValues(alpha: 0.35),
                                                    blurRadius: 14,
                                                    offset: const Offset(0, 5),
                                                  ),
                                                ],
                                              ),
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  onTap: _isStepLoading ? null : _stepSubmit,
                                                  borderRadius: BorderRadius.circular(26),
                                                  child: Center(
                                                    child: _isStepLoading
                                                        ? const SmartDoseLoading(size: 40, color: Colors.white)
                                                        : Row(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                              Text(
                                                                isLastStep ? 'Create account' : 'Continue',
                                                                style: const TextStyle(
                                                                  fontSize: 16,
                                                                  fontWeight: FontWeight.w600,
                                                                  color: Colors.white,
                                                                ),
                                                              ),
                                                              const SizedBox(width: 8),
                                                              Icon(
                                                                isLastStep
                                                                    ? Icons.check_circle_rounded
                                                                    : Icons.arrow_forward_rounded,
                                                                color: Colors.white,
                                                                size: 20,
                                                              ),
                                                            ],
                                                          ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),

                                      // "Already have an account? Log in" Link
                                      GestureDetector(
                                        onTap: (_isCreating || _isAnimating) ? null : _handleGoToLogin,
                                        child: RichText(
                                          textAlign: TextAlign.center,
                                          text: TextSpan(
                                            text: "Already have an account? ",
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                                            ),
                                            children: const [
                                              TextSpan(
                                                text: 'Log in',
                                                style: TextStyle(
                                                  color: Color(0xFF00A36C),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
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
                  ],
                ),
              ],
            ),
          ),
        ),
      );
  }
}

// ─── Step Indicator Widget ─────────────────────────────────────────────────────

class _StepIndicator extends StatefulWidget {
  final int currentStep;
  const _StepIndicator({required this.currentStep});

  @override
  State<_StepIndicator> createState() => _StepIndicatorState();
}

class _StepIndicatorState extends State<_StepIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressCtrl;
  late Animation<double> _progressAnim;
  double _targetProgress = 0.0;

  double _stepToProgress(int step) => (step - 1) / 2.0;

  @override
  void initState() {
    super.initState();
    _targetProgress = _stepToProgress(widget.currentStep);
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _progressAnim = Tween<double>(begin: _targetProgress, end: _targetProgress)
        .animate(CurvedAnimation(parent: _progressCtrl, curve: Curves.easeInOutCubic));
  }

  @override
  void didUpdateWidget(_StepIndicator old) {
    super.didUpdateWidget(old);
    if (old.currentStep != widget.currentStep) {
      final double from = _progressAnim.value;
      final double to = _stepToProgress(widget.currentStep);
      _progressAnim = Tween<double>(begin: from, end: to)
          .animate(CurvedAnimation(parent: _progressCtrl, curve: Curves.easeInOutCubic));
      _progressCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progressAnim,
      builder: (context, _) {
        final double p = _progressAnim.value; // 0.0 to 1.0
        final double line1Progress = (p / 0.5).clamp(0.0, 1.0);
        final double line2Progress = ((p - 0.5) / 0.5).clamp(0.0, 1.0);

        return Row(
          children: [
            _StepCircle(stepNum: 1, currentStep: widget.currentStep),
            _AnimatedStepLine(progress: line1Progress),
            _StepCircle(stepNum: 2, currentStep: widget.currentStep),
            _AnimatedStepLine(progress: line2Progress),
            _StepCircle(stepNum: 3, currentStep: widget.currentStep),
          ],
        );
      },
    );
  }
}

class _StepCircle extends StatelessWidget {
  final int stepNum;
  final int currentStep;
  const _StepCircle({required this.stepNum, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final bool isCompleted = currentStep > stepNum;
    final bool isCurrent = currentStep == stepNum;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgColor = (isCompleted || isCurrent)
        ? const Color(0xFF00A36C)
        : (isDark ? const Color(0xFF3F3F46) : const Color(0xFFE5E7EB));
    final Color textColor = (isCompleted || isCurrent)
        ? Colors.white
        : (isDark ? const Color(0xFFD4D4D8) : const Color(0xFF9CA3AF));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      width: isCurrent ? 40 : 36,
      height: isCurrent ? 40 : 36,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        boxShadow: (isCompleted || isCurrent)
            ? [BoxShadow(color: const Color(0xFF00A36C).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))]
            : [],
      ),
      child: Center(
        child: isCompleted
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
            : AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: isCurrent ? 16 : 14,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
                child: Text('$stepNum'),
              ),
      ),
    );
  }
}

/// Line that fills smoothly from left based on [progress] 0.0→1.0
class _AnimatedStepLine extends StatelessWidget {
  final double progress;
  const _AnimatedStepLine({required this.progress});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        height: 4,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(3),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: progress,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00C882), Color(0xFF00A36C)],
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Signup Success Screen ────────────────────────────────────────────────────

class _SignupSuccessScreen extends StatefulWidget {
  final String name;
  final VoidCallback onContinue;
  final VoidCallback? onGoToLogin;

  const _SignupSuccessScreen({
    super.key,
    required this.name,
    required this.onContinue,
    this.onGoToLogin,
  });

  @override
  State<_SignupSuccessScreen> createState() => _SignupSuccessScreenState();
}

class _SignupSuccessScreenState extends State<_SignupSuccessScreen>
    with TickerProviderStateMixin {
  late AnimationController _checkCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _checkScale;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _checkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _checkScale = CurvedAnimation(
      parent: _checkCtrl,
      curve: Curves.elasticOut,
    );

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeCtrl,
      curve: Curves.easeOut,
    );

    // Check bounces in → then text fades in → auto redirect to dashboard
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _checkCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _fadeCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) widget.onContinue();
    });
  }

  @override
  void dispose() {
    _checkCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated checkmark circle
            ScaleTransition(
              scale: _checkScale,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF00C882), Color(0xFF00A36C)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(0xFF00A36C).withValues(alpha: 0.35),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 56,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Title & subtitle
            FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  Text(
                    'Account Created!',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1F2937),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Welcome, ${widget.name}!\nRedirecting to your dashboard...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SmartDoseLoading(size: 36, color: Color(0xFF00A36C)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
