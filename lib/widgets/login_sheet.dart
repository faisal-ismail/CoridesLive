import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:corides/services/auth_service.dart';
import 'package:corides/services/firestore_service.dart';
import 'package:corides/models/user_model.dart';

class LoginSheet extends StatefulWidget {
  const LoginSheet({super.key});

  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  bool isOtpSent = false;
  String? verificationId;
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(10),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(35),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 30,
            spreadRadius: 5,
          )
        ],
        border: Border.all(color: Colors.grey[200]!, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 45,
            height: 5,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.grey, Colors.black26]),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 30),
          
          // Header Text
          Text(
            isOtpSent ? "Verification Required" : "Join CoRides",
            style: const TextStyle(
              fontSize: 26, 
              fontWeight: FontWeight.w800, 
              letterSpacing: -0.5,
              color: Color(0xFF001524),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isOtpSent ? "We've sent a 6-digit code to your device" : "Experience the future of ride-sharing with AI assistance",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 32),
          
          // Cross-fade for smoothness
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            firstChild: _buildPhoneInput(),
            secondChild: _buildOtpInput(),
            crossFadeState: isOtpSent ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          ),
          
          const SizedBox(height: 32),
          
          // Primary Action
          _buildActionButton(),
        ],
      ),
    );
  }

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
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400], letterSpacing: 2),
            prefixIcon: Icon(icon, color: const Color(0xFF15616D), size: 20),
            filled: true,
            fillColor: Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
      height: 60,
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
            blurRadius: 15,
            offset: const Offset(0, 5),
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
                isOtpSent ? "CONFIRM CODE" : "START JOURNEY",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 13),
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

    final auth = Provider.of<AuthService>(context, listen: false);
    setState(() => isLoading = true);
    
    try {
      await auth.signInWithPhoneNumber(
        _phoneController.text,
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
            String message = "Authentication failed";
            if (e.code == 'invalid-phone-number') {
              message = "The provided phone number is not valid.";
            } else if (e.code == 'too-many-requests') {
              message = "Too many requests. Try again later.";
            } else if (e.code == 'missing-client-identifier') {
              message = "Configuration error: Check SHA-1/SHA-256 in Firebase Console.";
            }
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? message)));
          }
        },
        onVerificationCompleted: (credential) async {
          // Auto-verify on some Android devices
          try {
            final auth = Provider.of<AuthService>(context, listen: false);
            final firestore = Provider.of<FirestoreService>(context, listen: false);
            final cred = await auth.signInWithCredential(credential);
            
            if (cred.user != null) {
              await _handleUserSignIn(cred.user!, firestore);
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Auto-verification failed: $e")));
            }
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

  Future<void> _handleUserSignIn(User user, FirestoreService firestore) async {
    try {
      // Create user in firestore if not exists
      final existingUser = await firestore.getUser(user.uid);
      if (existingUser == null) {
        await firestore.createUser(UserModel(
          uid: user.uid,
          phoneNumber: user.phoneNumber ?? _phoneController.text,
          createdAt: DateTime.now(),
        ));
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Profile sync failed: $e")));
      }
    }
  }

  Future<void> _verifyOtp() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final firestore = Provider.of<FirestoreService>(context, listen: false);
    setState(() => isLoading = true);

    try {
      final cred = await auth.confirmOTP(verificationId!, _otpController.text);
      if (cred.user != null) {
        await _handleUserSignIn(cred.user!, firestore);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid OTP")));
    } finally {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
    }
  }
}
