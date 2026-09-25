import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/app_preloader.dart';
import 'admin_dashboard_screen.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Secure Admin Login Screen for Web / Desktop
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Authentication & Admin Authorization Logic
  Future<void> _handleAdminLogin() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      // 1. Authenticate with Firebase Auth
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw Exception('User authentication failed.');
      }

      // 2. Query Firestore for logged-in user's UID to check isAdmin
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final bool isAdmin = userDoc.exists && (userDoc.data()?['isAdmin'] as bool? ?? false);

      if (isAdmin) {
        if (mounted) {
          SafeHaptics.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              content: Text('Admin authorization granted. Welcome!'),
            ),
          );

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const AdminDashboardScreen(),
            ),
          );
        }
      } else {
        // 3. Reject & Sign Out if not admin
        await FirebaseAuth.instance.signOut();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              content: Row(
                children: [
                  Icon(Icons.gpp_bad_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Access Denied: Admin privileges required.',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            content: Text('Login failed: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF1C1412);
    const accentColor = Color(0xFFF2B78A);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF382A24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo / Icon Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      size: 48,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    'Admin Control Center',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in with authorized administrator credentials',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.blueGrey.shade300,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Email Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'ADMIN EMAIL *',
                      style: TextStyle(
                        color: Colors.blueGrey.shade300,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'admin@chondrobindu.edu.bd',
                      hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 13),
                      prefixIcon: Icon(Icons.email_outlined, color: Colors.blueGrey.shade400, size: 20),
                      filled: true,
                      fillColor: const Color(0xFF241C1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF382A24)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF382A24)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: accentColor, width: 1.5),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty || !val.contains('@')) {
                        return 'Please enter a valid admin email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

                  // Password Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'PASSWORD *',
                      style: TextStyle(
                        color: Colors.blueGrey.shade300,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '••••••••••••',
                      hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 13),
                      prefixIcon: Icon(Icons.lock_outline_rounded, color: Colors.blueGrey.shade400, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: Colors.blueGrey.shade400,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                      filled: true,
                      fillColor: const Color(0xFF241C1A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF382A24)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF382A24)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: accentColor, width: 1.5),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  // Login as Admin Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: const Color(0xFF110D0C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isLoading ? null : _handleAdminLogin,
                      child: _isLoading
                          ? const AppPreloader(
                              size: 20,
                              strokeWidth: 2,
                              color: Color(0xFF110D0C),
                            )
                          : const Text(
                              'Login as Admin',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
