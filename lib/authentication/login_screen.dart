import 'package:country_picker/country_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/session_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneController = TextEditingController();

  static const Color primaryColor = Color(0xFF39FF14);
  static const Color textColor = Color(0xFF111111);
  static const Color secondaryTextColor = Color(0xFF6B6B6B);
  static const Color surfaceColor = Color(0xFFF7F8F7);
  static const Color borderColor = Color(0xFFEAECEA);

  bool _agree = false;
  bool _loading = false;

  Country _selectedCountry = Country(
    phoneCode: '211',
    countryCode: 'SS',
    e164Sc: 0,
    geographic: true,
    level: 1,
    name: 'South Sudan',
    example: '',
    displayName: 'South Sudan',
    displayNameNoCountryCode: 'South Sudan',
    e164Key: '',
  );

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _openCountryPicker() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      onSelect: (Country country) {
        setState(() {
          _selectedCountry = country;
        });
      },
    );
  }

  void _showTerms() {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          titlePadding: const EdgeInsets.fromLTRB(
            24,
            28,
            24,
            0,
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            24,
            14,
            24,
            8,
          ),
          actionsPadding: const EdgeInsets.only(
            bottom: 16,
          ),
          title: const Text(
            'Terms & Conditions',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          content: const Text(
            'By continuing, you agree to AlphaRide’s Terms & Conditions and Privacy Policy.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text(
                'Close',
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _setLoading(bool value) {
    if (!mounted || _loading == value) return;

    setState(() {
      _loading = value;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  String _messageForAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-phone-number':
        return 'Enter a valid phone number, including the correct country code.';
      case 'too-many-requests':
        return 'Too many verification attempts. Please wait a few minutes and try again.';
      case 'quota-exceeded':
        return 'The SMS limit has been reached. Please try again later.';
      case 'network-request-failed':
        return 'Check your internet connection and try again.';
      case 'operation-not-allowed':
        return 'Phone sign-in is not enabled for this app.';
      case 'app-not-authorized':
      case 'captcha-check-failed':
      case 'missing-client-identifier':
      case 'internal-error':
        return 'AlphaRide could not complete app verification. Close the verification page and try again. If it continues, the Android SHA configuration must be updated in Firebase.';
      default:
        return error.message ?? 'Phone verification failed. Please try again.';
    }
  }

  Future<void> _sendOTP() async {
    if (_loading) return;

    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_agree) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please accept the Terms & Conditions.',
          ),
        ),
      );
      return;
    }

    final String phoneNumber = '+${_selectedCountry.phoneCode}'
        '${_phoneController.text.trim()}';

    _setLoading(true);

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (
          PhoneAuthCredential credential,
        ) async {
          try {
            SessionService.instance.beginSignIn();

            try {
              final UserCredential result =
                  await FirebaseAuth.instance.signInWithCredential(credential);
              final User? user = result.user;

              if (user == null) {
                throw StateError('Firebase did not return a signed-in user.');
              }

              await SessionService.instance.activateSession(user);
            } catch (_) {
              SessionService.instance.cancelSignIn();
              rethrow;
            }

            if (!mounted) return;

            _setLoading(false);

            Navigator.pushReplacementNamed(
              context,
              '/home',
            );
          } on FirebaseAuthException catch (error) {
            _setLoading(false);
            _showMessage(_messageForAuthError(error));
          } catch (_) {
            _setLoading(false);
            _showMessage(
              'Automatic verification failed. Please request a new code.',
            );
          }
        },
        verificationFailed: (
          FirebaseAuthException error,
        ) {
          if (!mounted) return;

          _setLoading(false);
          _showMessage(_messageForAuthError(error));
        },
        codeSent: (
          String verificationId,
          int? resendToken,
        ) {
          if (!mounted) return;

          _setLoading(false);

          Navigator.pushNamed(
            context,
            '/otp',
            arguments: {
              'phone': phoneNumber,
              'verificationId': verificationId,
            },
          );
        },
        codeAutoRetrievalTimeout: (
          String verificationId,
        ) {
          if (!mounted) return;

          _setLoading(false);
        },
      );
    } on FirebaseAuthException catch (error) {
      _setLoading(false);
      _showMessage(_messageForAuthError(error));
    } catch (_) {
      _setLoading(false);
      _showMessage(
        'Unable to start phone verification. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (
            BuildContext context,
            BoxConstraints constraints,
          ) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Spacer(flex: 2),

                        // Phone illustration
                        Container(
                          width: 144,
                          height: 144,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(
                              alpha: 0.08,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Container(
                            width: 104,
                            height: 104,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(
                                alpha: 0.15,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.phone_rounded,
                              size: 54,
                              color: textColor,
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Page heading
                        const Text(
                          'Enter your phone number',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 29,
                            height: 1.18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.7,
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Supporting information
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          child: Text(
                            'We’ll send you a verification code by SMS to confirm your number.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 15.5,
                              height: 1.55,
                              fontWeight: FontWeight.w400,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),

                        const SizedBox(height: 34),

                        // Field label
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Phone number',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 14,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Phone number field
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          cursorColor: textColor,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          onFieldSubmitted: (_) {
                            if (!_loading) {
                              _sendOTP();
                            }
                          },
                          decoration: InputDecoration(
                            hintText: '912 345 678',
                            hintStyle: const TextStyle(
                              color: Color(0xFF9A9A9A),
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                            ),
                            filled: true,
                            fillColor: surfaceColor,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 19,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 0,
                              minHeight: 0,
                            ),
                            prefixIcon: InkWell(
                              onTap: _openCountryPicker,
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _selectedCountry.flagEmoji,
                                      style: const TextStyle(
                                        fontSize: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '+${_selectedCountry.phoneCode}',
                                      style: const TextStyle(
                                        color: textColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 20,
                                      color: secondaryTextColor,
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      width: 1,
                                      height: 28,
                                      color: borderColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: borderColor,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: textColor,
                                width: 1.4,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Color(0xFFD83A3A),
                              ),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Color(0xFFD83A3A),
                                width: 1.4,
                              ),
                            ),
                            errorStyle: const TextStyle(
                              color: Color(0xFFD83A3A),
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                          style: const TextStyle(
                            color: textColor,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                          validator: (String? value) {
                            final String number = value?.trim() ?? '';

                            if (number.isEmpty) {
                              return 'Enter your phone number.';
                            }

                            if (number.length < 9) {
                              return 'Enter a valid phone number.';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 10),

                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Standard SMS rates may apply.',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 12.5,
                              height: 1.4,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),

                        const Spacer(flex: 3),

                        // Terms and privacy information
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: surfaceColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: borderColor,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Checkbox(
                                value: _agree,
                                activeColor: primaryColor,
                                checkColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                side: const BorderSide(
                                  color: secondaryTextColor,
                                  width: 1.2,
                                ),
                                onChanged: (bool? value) {
                                  setState(() {
                                    _agree = value ?? false;
                                  });
                                },
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                child: GestureDetector(
                                  onTap: _showTerms,
                                  child: const Text.rich(
                                    TextSpan(
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 13,
                                        height: 1.45,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: 'I agree to AlphaRide’s ',
                                        ),
                                        TextSpan(
                                          text: 'Terms & Conditions',
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.w600,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                        TextSpan(text: ' and '),
                                        TextSpan(
                                          text: 'Privacy Policy',
                                          style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.w600,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                        TextSpan(text: '.'),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Continue button — unchanged
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _sendOTP,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.black,
                              disabledBackgroundColor: primaryColor.withValues(
                                alpha: 0.45,
                              ),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 23,
                                    height: 23,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Text(
                                    'Continue',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
