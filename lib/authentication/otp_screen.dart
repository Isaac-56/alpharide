import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/firestore_service.dart';
import '../services/session_service.dart';

class OTPScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;

  const OTPScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
  });

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestore = FirestoreService();

  final TextEditingController _controller = TextEditingController();

  final FocusNode _focusNode = FocusNode();

  final ValueNotifier<int> _secondsRemaining = ValueNotifier<int>(60);

  static const Color primaryColor = Color(0xFF39FF14);
  static const Color textColor = Color(0xFF111111);
  static const Color secondaryTextColor = Color(0xFF6B6B6B);
  static const Color surfaceColor = Color(0xFFF7F8F7);
  static const Color borderColor = Color(0xFFEAECEA);
  static const Color backButtonBorderColor = Color(0xFFB9B9B9);
  static const Color errorColor = Color(0xFFD83A3A);

  late String _verificationId;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  Timer? _timer;

  String _otp = '';
  bool _verifying = false;

  @override
  void initState() {
    super.initState();

    _verificationId = widget.verificationId;

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _shakeAnimation = TweenSequence<double>(
      [
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 0,
            end: -10,
          ),
          weight: 1,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: -10,
            end: 10,
          ),
          weight: 2,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 10,
            end: -8,
          ),
          weight: 2,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: -8,
            end: 8,
          ),
          weight: 2,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 8,
            end: 0,
          ),
          weight: 1,
        ),
      ],
    ).animate(
      CurvedAnimation(
        parent: _shakeController,
        curve: Curves.easeInOut,
      ),
    );

    _startTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openKeyboard();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _secondsRemaining.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _openKeyboard() {
    if (!mounted) return;

    _focusNode.requestFocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      SystemChannels.textInput.invokeMethod<void>(
        'TextInput.show',
      );
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsRemaining.value = 60;

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (Timer timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        final int remaining = _secondsRemaining.value;

        if (remaining <= 1) {
          timer.cancel();
          _secondsRemaining.value = 0;
          return;
        }

        _secondsRemaining.value = remaining - 1;
      },
    );
  }

  String _formatTimer(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;

    return '$minutes:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  void _showError(String message) {
    if (!mounted) return;

    _shakeController.forward(from: 0);

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: errorColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  Future<void> _verifyOTP() async {
    if (_verifying) return;

    FocusScope.of(context).unfocus();

    if (_otp.length != 6) {
      _showError(
        'Please enter all six verification digits.',
      );

      _openKeyboard();
      return;
    }

    setState(() {
      _verifying = true;
    });

    try {
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: _otp,
      );

      SessionService.instance.beginSignIn();

      try {
        final UserCredential result =
            await _auth.signInWithCredential(credential);
        final User? user = result.user;

        if (user == null) {
          throw StateError('Firebase did not return a signed-in user.');
        }

        await SessionService.instance.activateSession(user);
      } catch (_) {
        SessionService.instance.cancelSignIn();
        rethrow;
      }

      final bool userExists = await _firestore.checkUserExists(
        widget.phoneNumber,
      );

      if (!mounted) return;

      _timer?.cancel();

      if (userExists) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/home',
          (Route<dynamic> route) => false,
        );
      } else {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/signup',
          (Route<dynamic> route) => false,
          arguments: widget.phoneNumber,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      _showError(
        error.message ?? 'The verification code is invalid.',
      );

      _controller.clear();

      setState(() {
        _otp = '';
      });

      _openKeyboard();
    } catch (error) {
      if (!mounted) return;

      _showError(
        'Unable to verify the code. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _verifying = false;
        });
      }
    }
  }

  Future<void> _resendOTP() async {
    if (_secondsRemaining.value != 0 || _verifying) {
      return;
    }

    _startTimer();

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        verificationCompleted: (
          PhoneAuthCredential credential,
        ) async {
          try {
            SessionService.instance.beginSignIn();

            try {
              final UserCredential result =
                  await _auth.signInWithCredential(credential);
              final User? user = result.user;

              if (user == null) {
                throw StateError('Firebase did not return a signed-in user.');
              }

              await SessionService.instance.activateSession(user);
            } catch (_) {
              SessionService.instance.cancelSignIn();
              rethrow;
            }
          } on FirebaseAuthException catch (error) {
            if (!mounted) return;

            _secondsRemaining.value = 0;

            _showError(
              error.message ?? 'Automatic verification failed.',
            );
          }
        },
        verificationFailed: (
          FirebaseAuthException error,
        ) {
          if (!mounted) return;

          _timer?.cancel();
          _secondsRemaining.value = 0;

          _showError(
            error.message ?? 'Unable to resend the verification code.',
          );
        },
        codeSent: (
          String verificationId,
          int? resendToken,
        ) {
          if (!mounted) return;

          setState(() {
            _verificationId = verificationId;
          });

          final ScaffoldMessengerState messenger =
              ScaffoldMessenger.of(context);

          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: const Text(
                  'A new verification code was sent.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                backgroundColor: textColor,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            );
        },
        codeAutoRetrievalTimeout: (
          String verificationId,
        ) {
          _verificationId = verificationId;
        },
      );
    } catch (error) {
      if (!mounted) return;

      _timer?.cancel();
      _secondsRemaining.value = 0;

      _showError(
        'Unable to resend the code. Please try again.',
      );
    }
  }

  Widget _buildOTPBoxes() {
    return LayoutBuilder(
      builder: (
        BuildContext context,
        BoxConstraints constraints,
      ) {
        final double boxWidth =
            ((constraints.maxWidth - 40) / 6).clamp(36.0, 46.0).toDouble();

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openKeyboard,
          child: AnimatedBuilder(
            animation: _shakeAnimation,
            builder: (
              BuildContext context,
              Widget? child,
            ) {
              return Transform.translate(
                offset: Offset(
                  _shakeAnimation.value,
                  0,
                ),
                child: child,
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List<Widget>.generate(
                6,
                (int index) {
                  final String digit = index < _otp.length ? _otp[index] : '';

                  final bool isActive = index == _otp.length && _otp.length < 6;

                  final bool isFilled = index < _otp.length;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: boxWidth,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isFilled
                          ? primaryColor.withValues(
                              alpha: 0.10,
                            )
                          : surfaceColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isActive || isFilled ? textColor : borderColor,
                        width: isActive ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      digit,
                      style: const TextStyle(
                        color: textColor,
                        fontSize: 24,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildResendSection() {
    return ValueListenableBuilder<int>(
      valueListenable: _secondsRemaining,
      builder: (
        BuildContext context,
        int secondsRemaining,
        Widget? child,
      ) {
        final bool canResend = secondsRemaining == 0 && !_verifying;

        return Column(
          children: [
            Text(
              secondsRemaining == 0
                  ? 'Didn’t receive the code?'
                  : 'Request a new code in '
                      '${_formatTimer(secondsRemaining)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: secondaryTextColor,
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: canResend ? _resendOTP : null,
              style: TextButton.styleFrom(
                foregroundColor: textColor,
                disabledForegroundColor: secondaryTextColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: Text(
                'Resend code',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  decoration: canResend
                      ? TextDecoration.underline
                      : TextDecoration.none,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (
            BuildContext context,
            BoxConstraints constraints,
          ) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Material(
                          color: Colors.transparent,
                          shape: const CircleBorder(
                            side: BorderSide(
                              color: backButtonBorderColor,
                              width: 1.2,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: _verifying
                                ? null
                                : () {
                                    Navigator.pop(
                                      context,
                                    );
                                  },
                            customBorder: const CircleBorder(),
                            child: Icon(
                              Icons.arrow_back_rounded,
                              size: 23,
                              color:
                                  _verifying ? secondaryTextColor : textColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: keyboardVisible ? 18 : 36,
                    ),
                    if (!keyboardVisible) ...[
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
                            Icons.sms_outlined,
                            size: 50,
                            color: textColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),
                    ],
                    const Text(
                      'Verify your number',
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
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          color: secondaryTextColor,
                          fontSize: 15.5,
                          height: 1.55,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -0.1,
                        ),
                        children: [
                          const TextSpan(
                            text: 'Enter the six-digit code sent to\n',
                          ),
                          TextSpan(
                            text: widget.phoneNumber,
                            style: const TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(
                      height: keyboardVisible ? 20 : 32,
                    ),
                    _buildOTPBoxes(),
                    SizedBox(
                      width: 1,
                      height: 1,
                      child: Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: true,
                          showCursor: false,
                          enableInteractiveSelection: false,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          maxLength: 6,
                          autofillHints: const [
                            AutofillHints.oneTimeCode,
                          ],
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            counterText: '',
                            isCollapsed: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(
                              6,
                            ),
                          ],
                          onChanged: (String value) {
                            setState(() {
                              _otp = value;
                            });

                            if (value.length == 6) {
                              _verifyOTP();
                            }
                          },
                          onSubmitted: (_) {
                            _verifyOTP();
                          },
                        ),
                      ),
                    ),
                    SizedBox(
                      height: keyboardVisible ? 12 : 20,
                    ),
                    _buildResendSection(),
                    SizedBox(
                      height: keyboardVisible ? 16 : 32,
                    ),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _verifying ? null : _verifyOTP,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: primaryColor.withValues(
                            alpha: 0.45,
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              16,
                            ),
                          ),
                        ),
                        child: _verifying
                            ? const SizedBox(
                                width: 23,
                                height: 23,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.black,
                                ),
                              )
                            : const Text(
                                'Verify and continue',
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
            );
          },
        ),
      ),
    );
  }
}
