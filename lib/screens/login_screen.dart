
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:corides/services/auth_service.dart';
import 'package:corides/services/firestore_service.dart';
import 'package:corides/models/user_model.dart';
import 'package:corides/screens/gemini_chat_screen.dart'; // Just in case, but likely back to main.

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  bool isOtpSent = false;
  String? verificationId;
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.grey[200]!)),
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 16),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Icon(isOtpSent ? Icons.shield_rounded : Icons.phone_iphone_rounded, size: 64, color: const Color(0xFF15616D)),
              const SizedBox(height: 24),
              Text(
                isOtpSent ? "Verify Account" : "Access CoRides",
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Color(0xFF001524), letterSpacing: -1),
              ),
              const SizedBox(height: 12),
              Text(
                isOtpSent ? "We've sent a 6-digit code to your phone" : "Enter your details to sign in and book your next smart ride",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 48),
              
              // Cross-fade for smoothness
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                firstChild: _buildPhoneInput(),
                secondChild: _buildOtpInput(),
                crossFadeState: isOtpSent ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              ),
              
              const SizedBox(height: 40),
              
              // Primary Action
              _buildActionButton(),
              
              if (isOtpSent) ...[
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => setState(() => isOtpSent = false),
                  child: const Text("Use different number", style: TextStyle(color: Color(0xFF15616D), fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- Styled Helpers (Mirroring LoginSheet) ---

  Widget _buildPhoneInput() {
    return _buildTextField(
      controller: _phoneController,
      hint: "+92 300 1234567",
      icon: Icons.phone_iphone_rounded,
      label: "Phone Number",
      keyboardType: TextInputType.phone,
    );
  }

  Widget _buildOtpInput() {
    return _buildTextField(
      controller: _otpController,
      hint: "------",
      icon: Icons.shield_rounded,
      label: "OTP Code",
      keyboardType: TextInputType.number,
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required String label,
    required TextInputType keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Color(0xFF15616D)),
          ),
        ),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 1),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400], letterSpacing: 2),
            prefixIcon: Icon(icon, color: const Color(0xFF15616D), size: 22),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: Colors.grey[200]!, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: Color(0xFF15616D), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    return Container(
      width: double.infinity,
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF15616D), Color(0xFF001524)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF15616D).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        onPressed: isLoading ? null : (isOtpSent ? _verifyOtp : _sendOtp),
        child: isLoading
            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text(
                isOtpSent ? "CONFIRM & VERIFY" : "PROCEED SECURELY",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 14),
              ),
      ),
    );
  }

  Future<void> _sendOtp() async {
    if (_phoneController.text.isEmpty || !_phoneController.text.startsWith('+')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter phone number with country code (e.g. +92...)")),
      );
      return;
    }

    setState(() => isLoading = true);
    final auth = Provider.of<AuthService>(context, listen: false);

    try {
      await auth.signInWithPhoneNumber(
        _phoneController.text.trim(),
        onCodeSent: (id, token) {
          if (mounted) {
            setState(() {
              verificationId = id;
              isOtpSent = true;
              isLoading = false;
            });
          }
        },
        onVerificationFailed: (e) {
          if (mounted) {
            setState(() => isLoading = false);
            String message = e.message ?? "Authentication failed";
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
          }
        },
        onVerificationCompleted: (credential) async {
          // Auto-resolution on Android
          try {
            final userCred = await auth.signInWithCredential(credential);
            if (userCred.user != null) {
              await _handleUserSignIn(userCred.user!);
            }
          } catch (e) {
            // Handle error
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.isEmpty) return;
    
    setState(() => isLoading = true);
    final auth = Provider.of<AuthService>(context, listen: false);

    try {
      final cred = await auth.confirmOTP(verificationId!, _otpController.text.trim());
      if (cred.user != null) {
        await _handleUserSignIn(cred.user!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid OTP")));
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _handleUserSignIn(User user) async {
    final firestore = Provider.of<FirestoreService>(context, listen: false);
    try {
      final existingUser = await firestore.getUser(user.uid);
      if (existingUser == null) {
        // User doesn't exist, need to collect details
        if (mounted) {
          final result = await showModalBottomSheet<Map<String, String>>(
            context: context,
            isScrollControlled: true,
            isDismissible: false,
            enableDrag: false,
            builder: (context) => _SignupDetailsSheet(phoneNumber: user.phoneNumber ?? _phoneController.text),
          );

          if (result != null) {
            await firestore.createUser(UserModel(
              uid: user.uid,
              phoneNumber: user.phoneNumber ?? _phoneController.text,
              name: result['name']!,
              gender: result['gender']!,
              createdAt: DateTime.now(),
            ));
          } else {
            // User cancelled detail entry - sign out? Or just stay signed in without profile?
            // Safer to sign out if they don't complete profile
            await Provider.of<AuthService>(context, listen: false).signOut();
            return; 
          }
        }
      }
      if (mounted) {
        Navigator.pop(context); // Go back to Home/Main
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Profile sync failed: $e")));
      }
    }
  }
}

class _SignupDetailsSheet extends StatefulWidget {
  final String phoneNumber;
  const _SignupDetailsSheet({required this.phoneNumber});

  @override
  State<_SignupDetailsSheet> createState() => _SignupDetailsSheetState();
}

class _SignupDetailsSheetState extends State<_SignupDetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _gender = 'Male';
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Complete Profile", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Full Name",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (v) => v?.isNotEmpty == true ? null : "Name is required",
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _gender,
              decoration: const InputDecoration(
                labelText: "Gender",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.people),
              ),
              items: const [
                DropdownMenuItem(value: 'Male', child: Text("Male")),
                DropdownMenuItem(value: 'Female', child: Text("Female")),
                DropdownMenuItem(value: 'Other', child: Text("Other")),
              ],
              onChanged: (v) => setState(() => _gender = v!),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isSubmitting ? null : () {
                if (_formKey.currentState!.validate()) {
                  Navigator.pop(context, {'name': _nameController.text.trim(), 'gender': _gender});
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text("Create Account"),
            ),
          ],
        ),
      ),
    );
  }
}
