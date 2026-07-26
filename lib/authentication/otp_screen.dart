import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/firestore_service.dart';

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

  late String _verificationId;

  final TextEditingController _controller =
  TextEditingController();

  final FocusNode _focusNode = FocusNode();

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  String otp = "";

  bool _verifying = false;

  Timer? _timer;

  int secondsRemaining = 60;

  static const Color primaryColor =
  Color(0xFF39FF14);

  @override
  void initState() {
    super.initState();

    _verificationId = widget.verificationId;

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _shakeAnimation = Tween<double>(
      begin: 0,
      end: 18,
    ).animate(
      CurvedAnimation(
        parent: _shakeController,
        curve: Curves.elasticIn,
      ),
    );

    _startTimer();

    Future.delayed(
      const Duration(milliseconds: 300),
          () {
        if (mounted) {
          FocusScope.of(context)
              .requestFocus(_focusNode);
        }
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _startTimer() {
    secondsRemaining = 60;

    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {

        if (secondsRemaining == 0) {
          timer.cancel();
        } else {

          setState(() {
            secondsRemaining--;
          });

        }

      },
    );
  }

  String get timerText {

    int m = secondsRemaining ~/ 60;
    int s = secondsRemaining % 60;

    return "$m:${s.toString().padLeft(2, '0')}";
  }

  Future<void> verifyOTP() async {

    if (otp.length != 6) {

      _shakeController.forward(from: 0);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please enter all 6 digits.",
          ),
        ),
      );

      return;
    }

    setState(() {
      _verifying = true;
    });

    try {

      PhoneAuthCredential credential =
      PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: otp,
      );

      await _auth.signInWithCredential(
        credential,
      );

      bool exists =
      await _firestore.checkUserExists(
        widget.phoneNumber,
      );      if (!mounted) return;

      if (exists) {

        Navigator.pushNamedAndRemoveUntil(
          context,
          "/home",
              (route) => false,
        );

      } else {

        Navigator.pushNamedAndRemoveUntil(
          context,
          "/signup",
              (route) => false,
          arguments: widget.phoneNumber,
        );

      }

    } on FirebaseAuthException catch (e) {

      _shakeController.forward(from: 0);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ?? "Invalid verification code.",
          ),
        ),
      );

    } catch (e) {

      _shakeController.forward(from: 0);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString(),
          ),
        ),
      );

    }

    if (mounted) {
      setState(() {
        _verifying = false;
      });
    }

  }

  Future<void> resendOTP() async {

    if (secondsRemaining != 0) return;

    _startTimer();

    await _auth.verifyPhoneNumber(

      phoneNumber: widget.phoneNumber,

      verificationCompleted:
          (PhoneAuthCredential credential) async {

        await _auth.signInWithCredential(
          credential,
        );

      },

      verificationFailed:
          (FirebaseAuthException e) {

        ScaffoldMessenger.of(context)
            .showSnackBar(

          SnackBar(
            content: Text(
              e.message ??
                  "Verification failed.",
            ),
          ),

        );

      },

      codeSent:
          (String verificationId,
          int? resendToken) {

        _verificationId =
            verificationId;

        ScaffoldMessenger.of(context)
            .showSnackBar(

          const SnackBar(
            content:
            Text("OTP resent successfully."),
          ),

        );

      },

      codeAutoRetrievalTimeout:
          (String verificationId) {

        _verificationId =
            verificationId;

      },

    );

  }

  List<Widget> buildBoxes() {

    return List.generate(6, (index) {

      String digit = "";

      if (index < otp.length) {
        digit = otp[index];
      }

      return Container(

        width: 46,

        height: 58,

        alignment: Alignment.center,

        decoration: BoxDecoration(

          border: Border(

            bottom: BorderSide(

              width: 2,

              color: index == otp.length
                  ? primaryColor
                  : Colors.grey,

            ),

          ),

        ),

        child: Text(

          digit,

          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),

        ),

      );

    });

  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

        backgroundColor: Colors.white,

        body: SafeArea(

        child: Padding(

        padding:
        const EdgeInsets.all(24),          child: AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_shakeAnimation.value, 0),
              child: child,
            );
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              const Text(
                "Enter Verification Code",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                widget.phoneNumber,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 40),

              GestureDetector(
                onTap: () {
                  FocusScope.of(context)
                      .requestFocus(_focusNode);
                },
                child: Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceEvenly,
                  children: buildBoxes(),
                ),
              ),

              Opacity(
                opacity: 0,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters:  [
                    FilteringTextInputFormatter
                        .digitsOnly,
                  ],
                  onChanged: (value) {

                    setState(() {
                      otp = value;
                    });

                    if (value.length == 6) {
                      verifyOTP();
                    }

                  },
                ),
              ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    primaryColor,
                    foregroundColor:
                    Colors.black,
                  ),
                  onPressed: _verifying
                      ? null
                      : verifyOTP,
                  child: _verifying
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Text(
                    "Verify OTP",
                    style: TextStyle(
                      fontWeight:
                      FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Text(
                "Resend code in $timerText",
                style: const TextStyle(
                  color: Colors.grey,
                ),
              ),

              TextButton(
                onPressed:
                secondsRemaining == 0
                    ? resendOTP
                    : null,
                child: const Text(
                  "Resend OTP",
                ),
              ),

            ],
          ),
        ),
        ),
        ),
    );
  }
}