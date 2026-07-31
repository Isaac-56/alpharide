import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:passengerapp/services/firestore_service.dart';

class SignUpScreen extends StatefulWidget {
  final String phoneNumber;

  const SignUpScreen({
    required this.phoneNumber,
    super.key,
  });

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _referralCodeController = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  static const Color primaryColor = Color(0xFF39FF14);
  static const Color textColor = Color(0xFF111111);
  static const Color secondaryTextColor = Color(0xFF6B6B6B);
  static const Color surfaceColor = Color(0xFFF7F8F7);
  static const Color borderColor = Color(0xFFEAECEA);
  static const Color backButtonBorderColor = Color(0xFFB9B9B9);
  static const Color errorColor = Color(0xFFD83A3A);

  bool _isLoading = false;
  bool _isSelectingImage = false;
  bool _showConfirmButtons = false;

  File? _image;

  @override
  void dispose() {
    _nameController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

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
          backgroundColor: isError ? errorColor : textColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  Future<void> _selectImage(ImageSource source) async {
    if (_isSelectingImage || _isLoading) return;

    setState(() {
      _isSelectingImage = true;
    });

    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 78,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (pickedFile == null || !mounted) return;

      setState(() {
        _image = File(pickedFile.path);
        _showConfirmButtons = true;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;

      _showMessage(
        error.message ?? 'Unable to access your camera or photos.',
        isError: true,
      );
    } catch (error) {
      debugPrint('Image selection error: $error');

      if (!mounted) return;

      _showMessage(
        'Unable to select this photo.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSelectingImage = false;
        });
      }
    }
  }

  Future<String?> _uploadImage() async {
    final File? image = _image;

    if (image == null) return null;

    try {
      final Reference reference = FirebaseStorage.instance
          .ref()
          .child('user_photos')
          .child('${widget.phoneNumber}.jpg');

      final SettableMetadata metadata = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public,max-age=86400',
      );

      final TaskSnapshot snapshot = await reference.putFile(
        image,
        metadata,
      );

      return snapshot.ref.getDownloadURL();
    } catch (error) {
      debugPrint('Error uploading profile image: $error');
      rethrow;
    }
  }

  void _showPhotoOptions() {
    if (_isLoading || _isSelectingImage) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      builder: (BuildContext bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: borderColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Add profile photo',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 22,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose how you would like to add your photo.',
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 14.5,
                      height: 1.45,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _buildPhotoOption(
                  icon: Icons.camera_alt_outlined,
                  title: 'Take a photo',
                  description: 'Use your phone camera',
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _selectImage(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 12),
                _buildPhotoOption(
                  icon: Icons.photo_library_outlined,
                  title: 'Choose from gallery',
                  description: 'Select an existing photo',
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _selectImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhotoOption({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return Material(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: textColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: textColor,
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        color: secondaryTextColor,
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: secondaryTextColor,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _cancelPhoto() {
    if (_isLoading) return;

    setState(() {
      _image = null;
      _showConfirmButtons = false;
    });
  }

  void _confirmPhoto() {
    if (_isLoading) return;

    setState(() {
      _showConfirmButtons = false;
    });
  }

  void _goBack() {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    final NavigatorState navigator = Navigator.of(context);

    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed('/login');
    }
  }

  void _logOut() {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _register() async {
    if (_isLoading || _isSelectingImage) return;

    FocusScope.of(context).unfocus();

    final FormState? formState = _formKey.currentState;

    if (formState == null || !formState.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final bool userExists = await _firestoreService.checkUserExists(
        widget.phoneNumber,
      );

      if (!mounted) return;

      if (userExists) {
        _showMessage(
          'An account already exists for this number.',
          isError: true,
        );
        return;
      }

      final String? photoUrl = await _uploadImage();

      await _firestoreService.addUser(
        widget.phoneNumber,
        _nameController.text.trim(),
        photoUrl: photoUrl,
        referralCode: _referralCodeController.text.trim(),
      );

      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil(
        '/home',
        (Route<dynamic> route) => false,
      );
    } catch (error) {
      debugPrint('Error during registration: $error');

      if (!mounted) return;

      _showMessage(
        'Registration failed. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Color(0xFF9A9A9A),
        fontSize: 15.5,
        fontWeight: FontWeight.w400,
      ),
      prefixIcon: Icon(
        icon,
        size: 21,
        color: secondaryTextColor,
      ),
      filled: true,
      fillColor: surfaceColor,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 18,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderColor),
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
        borderSide: const BorderSide(color: errorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: errorColor,
          width: 1.4,
        ),
      ),
      errorStyle: const TextStyle(
        color: errorColor,
        fontSize: 12.5,
        height: 1.4,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(
                    [
                      const SizedBox(height: 8),

                      // Back button
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
                              onTap: _isLoading ? null : _goBack,
                              customBorder: const CircleBorder(),
                              child: Icon(
                                Icons.arrow_back_rounded,
                                size: 23,
                                color:
                                    _isLoading ? secondaryTextColor : textColor,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      const Text(
                        'Complete your profile',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 29,
                          height: 1.18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.7,
                        ),
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        'Add a few personal details to finish setting up your AlphaRide account.',
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 15.5,
                          height: 1.55,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -0.1,
                        ),
                      ),

                      const SizedBox(height: 30),

                      // Profile photo
                      Center(
                        child: Semantics(
                          button: true,
                          label: _image == null
                              ? 'Add profile photo'
                              : 'Change profile photo',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _isLoading || _isSelectingImage
                                ? null
                                : _showPhotoOptions,
                            child: Column(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 220),
                                      curve: Curves.easeOut,
                                      width: 120,
                                      height: 120,
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withValues(
                                          alpha: 0.08,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: CircleAvatar(
                                        backgroundColor:
                                            primaryColor.withValues(
                                          alpha: 0.14,
                                        ),
                                        backgroundImage: _image == null
                                            ? null
                                            : FileImage(_image!),
                                        child: _image == null
                                            ? const Icon(
                                                Icons.person_outline_rounded,
                                                size: 50,
                                                color: textColor,
                                              )
                                            : null,
                                      ),
                                    ),
                                    Positioned(
                                      right: 2,
                                      bottom: 2,
                                      child: Container(
                                        width: 38,
                                        height: 38,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: primaryColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 3,
                                          ),
                                        ),
                                        child: _isSelectingImage
                                            ? const SizedBox(
                                                width: 17,
                                                height: 17,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.black,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.camera_alt_outlined,
                                                size: 18,
                                                color: Colors.black,
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _image == null
                                      ? 'Add profile photo'
                                      : 'Change profile photo',
                                  style: const TextStyle(
                                    color: textColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Optional',
                                  style: TextStyle(
                                    color: secondaryTextColor,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: !_showConfirmButtons
                            ? const SizedBox.shrink()
                            : Padding(
                                key: const ValueKey<String>(
                                  'photo-confirmation',
                                ),
                                padding: const EdgeInsets.only(top: 16),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: surfaceColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed:
                                              _isLoading ? null : _cancelPhoto,
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Remove'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: errorColor,
                                            side: const BorderSide(
                                              color: errorColor,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed:
                                              _isLoading ? null : _confirmPhoto,
                                          icon: const Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                          ),
                                          label: const Text('Use photo'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: primaryColor,
                                            foregroundColor: Colors.black,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),

                      const SizedBox(height: 30),

                      const Text(
                        'Full name',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 10),

                      TextFormField(
                        controller: _nameController,
                        enabled: !_isLoading,
                        keyboardType: TextInputType.name,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        cursorColor: textColor,
                        decoration: _inputDecoration(
                          hintText: 'Enter your full name',
                          icon: Icons.person_outline_rounded,
                        ),
                        style: const TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        validator: (String? value) {
                          final String name = value?.trim() ?? '';

                          if (name.isEmpty) {
                            return 'Enter your full name.';
                          }

                          if (name.length < 2) {
                            return 'Enter a valid name.';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        'Referral code',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 4),

                      const Text(
                        'Optional',
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w400,
                        ),
                      ),

                      const SizedBox(height: 10),

                      TextFormField(
                        controller: _referralCodeController,
                        enabled: !_isLoading,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.characters,
                        cursorColor: textColor,
                        decoration: _inputDecoration(
                          hintText: 'Enter your referral code',
                          icon: Icons.card_giftcard_outlined,
                        ),
                        style: const TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
                        ),
                        onFieldSubmitted: (_) {
                          if (!_isLoading) {
                            _register();
                          }
                        },
                      ),

                      const SizedBox(height: 20),

                      // Verified phone number
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.verified_user_outlined,
                                color: textColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Verified phone number',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.phoneNumber,
                                    style: const TextStyle(
                                      color: secondaryTextColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.check_circle_rounded,
                              color: textColor,
                              size: 20,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading || _isSelectingImage
                              ? null
                              : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor:
                                primaryColor.withValues(alpha: 0.45),
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _isLoading
                                ? const SizedBox(
                                    key: ValueKey<String>('loading'),
                                    width: 23,
                                    height: 23,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Text(
                                    'Save and continue',
                                    key: ValueKey<String>('button-text'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      Center(
                        child: TextButton(
                          onPressed: _isLoading ? null : _logOut,
                          child: const Text(
                            'Log out',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
