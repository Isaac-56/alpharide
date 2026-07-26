//Older signup_screen

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:passengerapp/services/firestore_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_storage/firebase_storage.dart';

class SignUpScreen extends StatefulWidget {
  final String phoneNumber;

  const SignUpScreen({required this.phoneNumber, Key? key}) : super(key: key);

  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _referralCodeController = TextEditingController();
  bool _isLoading = false;
  File? _image;
  bool _showConfirmButtons = false;

  @override
  void dispose() {
    _nameController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.storage,
    ].request();

    if (statuses[Permission.camera] != PermissionStatus.granted ||
        statuses[Permission.storage] != PermissionStatus.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissions not granted')),
      );
    }
  }

  Future<void> _selectImage(ImageSource source) async {
    await _requestPermissions();

    final pickedFile = await ImagePicker().pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front, // Set the default to front camera
    );

    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _showConfirmButtons = true;
      });
    }
  }


  Future<String?> _uploadImage() async {
    if (_image == null) return null;

    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('user_photos')
          .child('${widget.phoneNumber}.jpg');
      await ref.putFile(_image!);
      return await ref.getDownloadURL();
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(context);
                _selectImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _selectImage(ImageSource.gallery);
              },
            ),
          ],
        );
      },
    );
  }

  void _cancelPhoto() {
    setState(() {
      _image = null;
      _showConfirmButtons = false;
    });
  }

  void _register() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        bool userExists = await _firestoreService.checkUserExists(widget.phoneNumber);
        if (userExists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User already exists')),
          );
          return;
        }

        String? photoUrl = await _uploadImage();
        await _firestoreService.addUser(
          widget.phoneNumber,
          _nameController.text,
          photoUrl: photoUrl,
          referralCode: _referralCodeController.text,
        );

        Navigator.of(context).pushReplacementNamed('/home');
      } catch (e) {
        print('Error during registration: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: $e')),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Add some personal info', style: TextStyle(color: Colors.black)),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _register,
            child: const Text('Save', style: TextStyle(color: Colors.purple)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _showPhotoOptions,
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: _image != null ? FileImage(_image!) : null,
                          child: _image == null
                              ? const Icon(Icons.camera_alt, size: 40, color: Colors.grey)
                              : null,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Add a photo',
                          style: TextStyle(color: Colors.purple),
                        ),
                        // Show confirm and cancel buttons if a photo is selected
                        if (_showConfirmButtons)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.cancel, color: Colors.red),
                                onPressed: _cancelPhoto,
                              ),
                              IconButton(
                                icon: const Icon(Icons.check, color: Colors.green),
                                onPressed: () {
                                  setState(() {
                                    _showConfirmButtons = false;
                                  });
                                },
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: UnderlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _referralCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Referral code, if you have one',
                    border: UnderlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed('/login');
                    },
                    child: const Text('Log out', style: TextStyle(color: Colors.purple)),
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
