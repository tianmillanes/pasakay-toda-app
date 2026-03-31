import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/connectivity_service.dart';
import '../../widgets/tricycle_logo.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';
import 'role_selection_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isBiometricAvailable = false;
  bool _hasSavedCredentials = false;
  bool _biometricInProgress = false;
  bool _rememberMe = true;
  late BiometricService _biometricService;

  @override
  void initState() {
    super.initState();
    _biometricService = BiometricService();
    _checkBiometricAvailability();
    _loadRememberMePreference();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoTriggerBiometricIfAvailable();
    });
  }

  Future<void> _loadRememberMePreference() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isEnabled = await authService.isRememberMeEnabled();
    if (mounted) {
      setState(() {
        _rememberMe = isEnabled;
      });
    }
  }
  
  Future<void> _autoTriggerBiometricIfAvailable() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted && _isBiometricAvailable && _hasSavedCredentials && !_isLoading) {
      await _biometricLogin();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometricAvailability() async {
    final isAvailable = await _biometricService.isBiometricAvailable();
    final hasSaved = await _biometricService.hasCredentialsSaved();
    if (mounted) {
      setState(() {
        _isBiometricAvailable = isAvailable;
        _hasSavedCredentials = hasSaved;
      });
    }
  }

  Future<bool> _showEnableBiometricDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Enable Biometric?', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('Would you like to enable fingerprint or face authentication for faster login next time?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Not Now', style: TextStyle(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Enable'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  Future<void> _biometricLogin() async {
    if (_biometricInProgress) return;
    if (!_isBiometricAvailable || !_hasSavedCredentials) return;

    setState(() {
      _isLoading = true;
      _biometricInProgress = true;
    });

    try {
      final credentials = await _biometricService.getCredentials();
      if (credentials == null) {
        if (mounted) SnackbarHelper.showError(context, 'No saved credentials found.');
        return;
      }

      final biometricResult = await _biometricService.authenticate(
        reason: 'Authenticate to login',
      ).timeout(const Duration(seconds: 10));

      if (!biometricResult.success) {
        if (mounted && biometricResult.status != BiometricStatus.userCancelled) {
          SnackbarHelper.showError(context, biometricResult.userMessage);
        }
        return;
      }

      final connectivityService = Provider.of<ConnectivityService>(context, listen: false);
      if (mounted && !await connectivityService.checkConnectivity(context)) {
        return;
      }

      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signInWithEmailAndPassword(
        credentials['email']!,
        credentials['password']!,
      );

      // User data is now guaranteed to be loaded by signInWithEmailAndPassword
      
      if (mounted) {
        final redirectRoute = authService.getRedirectRoute();
        if (redirectRoute == '/login') {
          // If still returning to login, there might be an issue with user data
          SnackbarHelper.showError(context, 'Login successful but failed to load user profile. Please try again.');
        } else {
          SnackbarHelper.showSuccess(context, 'Success! Logged in.');
          Navigator.of(context).pushReplacementNamed(redirectRoute);
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Biometric login failed. Please try again.';
        
        // Handle specific error types
        if (e.toString().contains('user-cancelled')) {
          errorMessage = 'Biometric login was cancelled.';
        } else if (e.toString().contains('not-available')) {
          errorMessage = 'Biometric authentication is not available on this device.';
        } else if (e.toString().contains('not-enrolled')) {
          errorMessage = 'No biometric credentials enrolled. Please set up fingerprint/face ID first.';
        } else if (e.toString().contains('timeout')) {
          errorMessage = 'Biometric login timed out. Please try again.';
        }
        
        SnackbarHelper.showError(context, errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _biometricInProgress = false;
        });
      }
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final connectivityService = Provider.of<ConnectivityService>(context, listen: false);
      
      // Check connectivity before attempting login
      if (!await connectivityService.checkConnectivity(context)) {
        return;
      }
      
      // Sign in with Firebase
      await authService.signInWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text,
        rememberMe: _rememberMe,
      );

      // User data is now guaranteed to be loaded by signInWithEmailAndPassword
      
      if (mounted) {
        if (_isBiometricAvailable && !_hasSavedCredentials) {
          final enableBiometric = await _showEnableBiometricDialog();
          if (enableBiometric) {
            await _biometricService.saveCredentials(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            );
            setState(() => _hasSavedCredentials = true);
          }
        }
        
        final redirectRoute = authService.getRedirectRoute();
        if (redirectRoute == '/login') {
          // If still returning to login, there might be an issue with user data
          SnackbarHelper.showError(context, 'Login successful but failed to load user profile. Please try again.');
        } else {
          Navigator.of(context).pushReplacementNamed(redirectRoute);
        }
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      
      // Provide more specific error messages
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email address.';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password. Please try again.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address format.';
          break;
        case 'user-disabled':
          errorMessage = e.message ?? 'This account has been deactivated. Please contact todapasakay@gmail.com for support.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many failed attempts. Please try again later.';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Your connection might be unstable or slow.';
          break;
        case 'email-already-in-use':
          errorMessage = 'This email is already registered.';
          break;
        case 'operation-not-allowed':
          errorMessage = 'Email/password accounts are not enabled. Please contact todapasakay@gmail.com for support.';
          break;
        case 'weak-password':
          errorMessage = 'Password is too weak.';
          break;
        case 'invalid-credential':
          errorMessage = 'Invalid email or password. Please check your credentials and try again.';
          break;
        default:
          // Use the message from Firebase if available, otherwise a generic one
          errorMessage = e.message ?? 'Login failed. Please check your credentials.';
      }
      
      if (mounted) SnackbarHelper.showError(context, errorMessage);
    } catch (e) {
      if (mounted) {
        final connectivityService = Provider.of<ConnectivityService>(context, listen: false);
        final errorMessage = connectivityService.getErrorMessage(e);
        
        SnackbarHelper.showError(context, errorMessage);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final connectivityService = Provider.of<ConnectivityService>(context, listen: false);
      if (!await connectivityService.checkConnectivity(context)) {
        setState(() => _isLoading = false);
        return;
      }
      final result = await authService.signInWithGoogle();
      if (result == null) {
        setState(() => _isLoading = false);
        return;
      }
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(authService.getRedirectRoute());
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Google Sign-In failed.');
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                
                // Top Logo
                Center(
                  child: const TricycleLogo(size: 140, showText: false, showShadow: false, plain: true),
                ),
                
                const SizedBox(height: 32),
                
                const Text(
                  "PASAKAY",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 35,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A1A1A),
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Ginhawang sakay mula sa bahay",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 40),

                // Manual Login Option
                _buildInputField(
                  label: 'Email Address',
                  controller: _emailController,
                  hint: 'Enter your email',
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),
                _buildInputField(
                  label: 'Password',
                  controller: _passwordController,
                  hint: 'Enter your password',
                  icon: Icons.lock_outline_rounded,
                  isPassword: true,
                ),

                const SizedBox(height: 12),
                
                // Remember Me & Forgot Password
                Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _rememberMe,
                        onChanged: (value) => setState(() => _rememberMe = value ?? true),
                        activeColor: AppTheme.primaryGreen,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        side: BorderSide(color: Colors.grey.shade400, width: 1.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Remember Me',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryGreen,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 64),
                          shape: const StadiumBorder(),
                          elevation: 8,
                          shadowColor: AppTheme.primaryGreen.withOpacity(0.3),
                        ),
                        child: _isLoading 
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      ),
                    ),
                    if (_isBiometricAvailable && _hasSavedCredentials) ...[
                      const SizedBox(width: 12),
                      Container(
                        height: 64,
                        width: 64,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(Icons.fingerprint_rounded, color: AppTheme.primaryGreen, size: 32),
                          onPressed: _isLoading ? null : _biometricLogin,
                          tooltip: 'Login with Biometrics',
                        ),
                      ),
                    ],
                  ],
                ),
                
                const SizedBox(height: 16),
                
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1A1A1A),
                    minimumSize: const Size(double.infinity, 64),
                    shape: const StadiumBorder(),
                    side: BorderSide(color: Colors.grey.shade200, width: 2),
                  ),
                  child: const Text('Create New Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ),

                const SizedBox(height: 32),

                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR CONTINUE WITH', style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: BorderSide(color: Colors.grey.shade200, width: 2),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('G', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.red)),
                        const SizedBox(width: 8),
                        const Text('Continue with Google', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isPassword && _obscurePassword,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          validator: isPassword ? (value) {
            if (value == null || value.isEmpty) {
              return 'Password is required';
            }
            if (value.length < 6) {
              return 'Password must be at least 6 characters';
            }
            return null;
          } : (value) {
            if (value == null || value.isEmpty) {
              return 'Email is required';
            }
            if (!RegExp(r'^[\w\-\.\+]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
              return 'Please enter a valid email address';
            }
            return null;
          },
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
            suffixIcon: isPassword ? IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.grey, size: 20),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ) : null,
          ),
        ),
      ],
    );
  }

}
