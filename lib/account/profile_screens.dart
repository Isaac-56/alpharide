import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../home/map_location_picker.dart';
import '../models/location_selection.dart';
import '../services/firestore_service.dart';
import 'account_ui.dart';

class ProfileMenuScreen extends StatefulWidget {
  final FirebaseAuth auth;
  final FirestoreService firestoreService;
  final Map<String, dynamic>? initialUserData;

  const ProfileMenuScreen({
    super.key,
    required this.auth,
    required this.firestoreService,
    required this.initialUserData,
  });

  @override
  State<ProfileMenuScreen> createState() => _ProfileMenuScreenState();
}

class _ProfileMenuScreenState extends State<ProfileMenuScreen> {
  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'Profile',
      child: Column(
        children: <Widget>[
          AlphaMenuTile(
            icon: Icons.person_outline_rounded,
            title: 'Personal information',
            subtitle: 'Photo, name, email, and emergency contact',
            onTap: () async {
              final String? phoneNumber = widget.auth.currentUser?.phoneNumber;

              if (phoneNumber == null) {
                showAlphaMessage(
                  context,
                  'Please sign in again to edit your profile.',
                  error: true,
                );
                return;
              }

              final bool? changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute<bool>(
                  builder: (_) => PersonalInformationScreen(
                    phoneNumber: phoneNumber,
                    auth: widget.auth,
                    firestoreService: widget.firestoreService,
                    initialUserData: widget.initialUserData,
                  ),
                ),
              );

              if (!mounted) return;
              if (changed == true) Navigator.pop(this.context, true);
            },
          ),
          AlphaMenuTile(
            icon: Icons.add_location_alt_outlined,
            title: 'Saved places',
            subtitle: 'Keep your regular pickup and destination points',
            showDivider: false,
            onTap: () {
              final String? phoneNumber = widget.auth.currentUser?.phoneNumber;

              if (phoneNumber == null) {
                showAlphaMessage(
                  context,
                  'Please sign in again to view saved places.',
                  error: true,
                );
                return;
              }

              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SavedPlacesScreen(
                    phoneNumber: phoneNumber,
                    firestoreService: widget.firestoreService,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class PersonalInformationScreen extends StatefulWidget {
  final String phoneNumber;
  final FirebaseAuth auth;
  final FirestoreService firestoreService;
  final Map<String, dynamic>? initialUserData;

  const PersonalInformationScreen({
    super.key,
    required this.phoneNumber,
    required this.auth,
    required this.firestoreService,
    required this.initialUserData,
  });

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _emergencyController;

  File? _selectedImage;
  String? _photoUrl;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic> data =
        widget.initialUserData ?? <String, dynamic>{};

    _nameController = TextEditingController(
      text: data['name']?.toString() ?? '',
    );
    _emailController = TextEditingController(
      text: data['email']?.toString() ?? '',
    );
    _emergencyController = TextEditingController(
      text: data['emergencyPhone']?.toString() ?? '',
    );
    _photoUrl = data['photoUrl']?.toString();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _emergencyController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 78,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (picked == null || !mounted) return;
      setState(() => _selectedImage = File(picked.path));
    } catch (error) {
      if (!mounted) return;
      showAlphaMessage(
        context,
        'Unable to select this photo.',
        error: true,
      );
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
            decoration: BoxDecoration(
              color: AlphaColors.surface(sheetContext),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AlphaColors.border(sheetContext),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Update profile photo',
                    style: TextStyle(
                      color: AlphaColors.text(sheetContext),
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AlphaMenuTile(
                  icon: Icons.camera_alt_outlined,
                  title: 'Take a photo',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickImage(ImageSource.camera);
                  },
                ),
                AlphaMenuTile(
                  icon: Icons.photo_library_outlined,
                  title: 'Choose from gallery',
                  showDivider: false,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _uploadSelectedPhoto() async {
    final File? image = _selectedImage;
    if (image == null) return _photoUrl;

    final Reference reference = FirebaseStorage.instance
        .ref()
        .child('user_photos')
        .child('${widget.phoneNumber}.jpg');

    final TaskSnapshot upload = await reference.putFile(
      image,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public,max-age=86400',
      ),
    );

    return upload.ref.getDownloadURL();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    try {
      final String? photoUrl = await _uploadSelectedPhoto();

      await widget.firestoreService.updateUserProfile(
        widget.phoneNumber,
        name: _nameController.text,
        email: _emailController.text,
        emergencyPhone: _emergencyController.text,
        photoUrl: photoUrl,
      );

      if (!mounted) return;
      showAlphaMessage(context, 'Profile updated successfully.');
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      showAlphaMessage(
        context,
        'Unable to save your profile. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteAccount() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: AlphaColors.surface(dialogContext),
          title: Text(
            'Delete your account?',
            style: TextStyle(color: AlphaColors.text(dialogContext)),
          ),
          content: Text(
            'This permanently removes your AlphaRide sign-in. This action cannot be undone.',
            style: TextStyle(
              color: AlphaColors.muted(dialogContext),
              height: 1.45,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep account'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: AlphaColors.danger),
              child: const Text('Delete permanently'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || _deleting) return;
    setState(() => _deleting = true);

    try {
      final User? user = widget.auth.currentUser;

      if (user == null) {
        throw StateError('No authenticated user');
      }

      await user.delete();

      try {
        await widget.firestoreService.deleteUserProfile(widget.phoneNumber);
      } catch (_) {
        // Authentication has already been removed. Server cleanup can retry.
      }

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (Route<dynamic> route) => false,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      final String message = error.code == 'requires-recent-login'
          ? 'For security, log out, sign in again, then retry account deletion.'
          : 'Unable to delete your account right now.';

      showAlphaMessage(context, message, error: true);
    } catch (error) {
      if (!mounted) return;
      showAlphaMessage(
        context,
        'Unable to delete your account right now.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _logout() async {
    await widget.auth.signOut();
    if (!mounted) return;

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/login',
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ImageProvider? imageProvider = _selectedImage != null
        ? FileImage(_selectedImage!)
        : (_photoUrl?.trim().isNotEmpty ?? false)
            ? NetworkImage(_photoUrl!.trim())
            : null;

    return AlphaPageScaffold(
      title: 'Personal information',
      action: TextButton(
        onPressed: _saving ? null : _save,
        child: const Text(
          'Save',
          style: TextStyle(
            color: AlphaColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Column(
                children: <Widget>[
                  Stack(
                    children: <Widget>[
                      Container(
                        width: 104,
                        height: 104,
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AlphaColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: CircleAvatar(
                          foregroundImage: imageProvider,
                          backgroundColor: AlphaColors.surface(context),
                          child: imageProvider == null
                              ? Icon(
                                  Icons.person_rounded,
                                  color: AlphaColors.text(context),
                                  size: 48,
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: AlphaColors.ink,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: _showPhotoOptions,
                            child: const SizedBox(
                              width: 38,
                              height: 38,
                              child: Icon(
                                Icons.camera_alt_rounded,
                                color: AlphaColors.primary,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _showPhotoOptions,
                    child: const Text('Change photo'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              style: TextStyle(color: AlphaColors.text(context)),
              decoration: alphaInputDecoration(
                context,
                label: 'Full name',
                prefixIcon: Icons.badge_outlined,
              ),
              validator: (String? value) {
                if ((value ?? '').trim().length < 2) {
                  return 'Enter your full name';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: widget.phoneNumber,
              readOnly: true,
              style: TextStyle(color: AlphaColors.text(context)),
              decoration: alphaInputDecoration(
                context,
                label: 'Phone number',
                prefixIcon: Icons.phone_outlined,
              ).copyWith(
                suffixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Image.asset(
                    'assets/images/south_sudan_flag.png',
                    width: 30,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              style: TextStyle(color: AlphaColors.text(context)),
              decoration: alphaInputDecoration(
                context,
                label: 'Email (optional)',
                hint: 'name@example.com',
                prefixIcon: Icons.email_outlined,
              ),
              validator: (String? value) {
                final String email = (value ?? '').trim();
                if (email.isEmpty) return null;
                if (!email.contains('@') || !email.contains('.')) {
                  return 'Enter a valid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _emergencyController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              style: TextStyle(color: AlphaColors.text(context)),
              decoration: alphaInputDecoration(
                context,
                label: 'Emergency contact (optional)',
                hint: '+211 ...',
                prefixIcon: Icons.health_and_safety_outlined,
              ),
            ),
            const SizedBox(height: 22),
            AlphaPrimaryButton(
              label: 'Save changes',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _save,
            ),
            const SizedBox(height: 30),
            Divider(color: AlphaColors.border(context)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: _deleting ? null : _deleteAccount,
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AlphaColors.danger,
              ),
              title: const Text(
                'Delete my account',
                style: TextStyle(
                  color: AlphaColors.danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
              trailing: _deleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AlphaColors.danger,
                      ),
                    )
                  : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: _logout,
              leading: Icon(
                Icons.logout_rounded,
                color: AlphaColors.text(context),
              ),
              title: Text(
                'Log out',
                style: TextStyle(
                  color: AlphaColors.text(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SavedPlacesScreen extends StatelessWidget {
  final String phoneNumber;
  final FirestoreService firestoreService;

  const SavedPlacesScreen({
    super.key,
    required this.phoneNumber,
    required this.firestoreService,
  });

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'Saved places',
      scrollable: false,
      action: TextButton.icon(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => AddSavedPlaceScreen(
              phoneNumber: phoneNumber,
              firestoreService: firestoreService,
            ),
          ),
        ),
        icon: const Icon(Icons.add_rounded, color: AlphaColors.primary),
        label: const Text(
          'Add a place',
          style: TextStyle(
            color: AlphaColors.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: firestoreService.watchSavedPlaces(phoneNumber),
        builder: (
          BuildContext context,
          AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
        ) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AlphaColors.primary),
            );
          }

          if (snapshot.hasError) {
            return const AlphaEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Saved places are unavailable',
              message: 'Check your connection and open this page again.',
            );
          }

          final List<Map<String, dynamic>> places =
              snapshot.data ?? <Map<String, dynamic>>[];

          if (places.isEmpty) {
            return AlphaEmptyState(
              icon: Icons.bookmark_add_outlined,
              title: 'Save your favorite places',
              message:
                  'Add home, work, or another place to choose it faster when ordering a ride.',
              action: SizedBox(
                width: 190,
                child: AlphaPrimaryButton(
                  label: 'Add a place',
                  icon: Icons.add_location_alt_rounded,
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => AddSavedPlaceScreen(
                        phoneNumber: phoneNumber,
                        firestoreService: firestoreService,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: places.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (BuildContext context, int index) {
              final Map<String, dynamic> place = places[index];

              return Dismissible(
                key: ValueKey<String>(place['id']?.toString() ?? '$index'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDelete(context),
                onDismissed: (_) {
                  firestoreService.deleteSavedPlace(
                    phoneNumber,
                    place['id'].toString(),
                  );
                },
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 22),
                  decoration: BoxDecoration(
                    color: AlphaColors.danger,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.delete_rounded, color: Colors.white),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AlphaColors.surface(context),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AlphaColors.border(context)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AlphaColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _placeIcon(place['label']?.toString() ?? ''),
                          color: AlphaColors.primary,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              place['label']?.toString() ?? 'Saved place',
                              style: TextStyle(
                                color: AlphaColors.text(context),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              place['address']?.toString() ??
                                  'Address unavailable',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AlphaColors.muted(context),
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('Remove this saved place?'),
            content: const Text(
              'You can add it again later.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: TextButton.styleFrom(
                  foregroundColor: AlphaColors.danger,
                ),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class AddSavedPlaceScreen extends StatefulWidget {
  final String phoneNumber;
  final FirestoreService firestoreService;

  const AddSavedPlaceScreen({
    super.key,
    required this.phoneNumber,
    required this.firestoreService,
  });

  @override
  State<AddSavedPlaceScreen> createState() => _AddSavedPlaceScreenState();
}

class _AddSavedPlaceScreenState extends State<AddSavedPlaceScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  LocationSelection? _selection;
  bool _saving = false;

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<LatLng> _initialLocation() async {
    try {
      final bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return const LatLng(4.8517, 31.5825);

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LatLng(4.8517, 31.5825);
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return LatLng(position.latitude, position.longitude);
    } catch (_) {
      return const LatLng(4.8517, 31.5825);
    }
  }

  Future<void> _chooseOnMap() async {
    final LatLng initialLocation = await _initialLocation();
    if (!mounted) return;

    final LocationSelection? result = await Navigator.push<LocationSelection>(
      context,
      MaterialPageRoute<LocationSelection>(
        builder: (_) => MapLocationPicker(
          initialLocation: _selection == null
              ? initialLocation
              : LatLng(_selection!.latitude, _selection!.longitude),
          initialAddress: _selection?.address ?? _addressController.text,
          isPickup: false,
        ),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _selection = result;
      _addressController.text = result.address;
    });
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;

    final LocationSelection? selection = _selection;
    if (selection == null) {
      showAlphaMessage(
        context,
        'Set the exact place on the map before saving.',
        error: true,
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await widget.firestoreService.addSavedPlace(
        widget.phoneNumber,
        label: _labelController.text,
        address: _addressController.text,
        latitude: selection.latitude,
        longitude: selection.longitude,
      );

      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      showAlphaMessage(
        context,
        'Unable to save this place. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'Add a place',
      child: Form(
        key: _formKey,
        child: Column(
          children: <Widget>[
            TextFormField(
              controller: _labelController,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(color: AlphaColors.text(context)),
              decoration: alphaInputDecoration(
                context,
                label: 'Place name',
                hint: 'Home, Work, School...',
                prefixIcon: Icons.label_outline_rounded,
              ),
              validator: (String? value) => (value ?? '').trim().isEmpty
                  ? 'Enter a name for this place'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _addressController,
              readOnly: true,
              maxLines: 2,
              style: TextStyle(color: AlphaColors.text(context)),
              decoration: alphaInputDecoration(
                context,
                label: 'Address',
                hint: 'Choose the exact point on the map',
                prefixIcon: Icons.location_on_outlined,
              ),
              validator: (String? value) => (value ?? '').trim().isEmpty
                  ? 'Choose a point on the map'
                  : null,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton.icon(
                onPressed: _chooseOnMap,
                icon: const Icon(Icons.map_outlined),
                label: Text(
                  _selection == null ? 'Set point on map' : 'Change map point',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AlphaColors.text(context),
                  side: const BorderSide(color: AlphaColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 22),
            AlphaPrimaryButton(
              label: 'Save place',
              icon: Icons.bookmark_add_rounded,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

IconData _placeIcon(String label) {
  final String normalized = label.toLowerCase();

  if (normalized.contains('home')) return Icons.home_outlined;
  if (normalized.contains('work') || normalized.contains('office')) {
    return Icons.work_outline_rounded;
  }
  if (normalized.contains('school') || normalized.contains('university')) {
    return Icons.school_outlined;
  }

  return Icons.place_outlined;
}
