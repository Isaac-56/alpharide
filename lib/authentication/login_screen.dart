import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneController = TextEditingController();

  bool _agree = false;
  bool _loading = false;

  Country _selectedCountry = Country(
    phoneCode: "211",
    countryCode: "SS",
    e164Sc: 0,
    geographic: true,
    level: 1,
    name: "South Sudan",
    example: "",
    displayName: "South Sudan",
    displayNameNoCountryCode: "South Sudan",
    e164Key: "",
  );

  static const Color primaryColor = Color(0xFF39FF14);

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agree) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please accept the Terms & Conditions."),
        ),
      );
      return;
    }

    String phone =
        "+${_selectedCountry.phoneCode}${_phoneController.text.trim()}";

    setState(() {
      _loading = true;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,

        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);

          if (!mounted) return;

          Navigator.pushReplacementNamed(
            context,
            "/home",
          );
        },

        verificationFailed: (FirebaseAuthException e) {
          setState(() => _loading = false);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e.message ?? "Verification failed.",
              ),
            ),
          );
        },

        codeSent: (String verificationId, int? resendToken) {
          setState(() => _loading = false);

          Navigator.pushNamed(
            context,
            "/otp",
            arguments: {
              "phone": phone,
              "verificationId": verificationId,
            },
          );
        },

        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  void _openCountryPicker() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      onSelect: (Country c) {
        setState(() {
          _selectedCountry = c;
        });
      },
    );
  }

  void _showTerms() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Terms & Conditions"),
        content: const Text(
          "By continuing you agree to Alpha Ride's Terms & Conditions.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                const SizedBox(height: 40),

                const Text(
                  "Enter your phone number",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 28,
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  "We'll send you a verification code.",
                  style: TextStyle(color: Colors.grey),
                ),

                const SizedBox(height: 40),

                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [

                      InkWell(
                        onTap: _openCountryPicker,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Text(_selectedCountry.flagEmoji),
                              const SizedBox(width: 8),
                              Text("+${_selectedCountry.phoneCode}"),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ),
                      ),

                      Expanded(
                        child: TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: const InputDecoration(
                            hintText: "Phone Number",
                            border: InputBorder.none,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return "Enter phone number";
                            }

                            if (value.length < 9) {
                              return "Invalid phone number";
                            }

                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                Row(
                  children: [
                    Checkbox(
                      value: _agree,
                      activeColor: primaryColor,
                      onChanged: (v) {
                        setState(() {
                          _agree = v ?? false;
                        });
                      },
                    ),

                    Expanded(
                      child: GestureDetector(
                        onTap: _showTerms,
                        child: const Text(
                          "I agree to the Terms & Conditions",
                        ),
                      ),
                    )
                  ],
                ),

                const SizedBox(height: 15),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _loading ? null : _sendOTP,
                    child: _loading
                        ? const CircularProgressIndicator()
                        : const Text(
                      "Continue",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}