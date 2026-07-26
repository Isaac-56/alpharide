import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CustomDrawer extends StatelessWidget {
  final Map<String, dynamic>? userData;
  final FirebaseAuth auth;
  final VoidCallback? onSignOut; // Add onSignOut parameter

  const CustomDrawer({
    Key? key,
    required this.userData,
    required this.auth,
    this.onSignOut, // Initialize the onSignOut parameter
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(
              userData?['name'] ?? 'User',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            accountEmail: Text(
              userData?['phoneNumber'] ?? '',
              style: const TextStyle(color: Colors.black87),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundImage: NetworkImage(userData?['photoUrl'] ?? 'https://via.placeholder.com/150'),
              backgroundColor: Colors.white,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF39FF14),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.black),
            title: const Text('Profile'),
            onTap: () {
              Navigator.pop(context);
              // Navigate to profile screen
              // Navigator.pushNamed(context, '/profile');
            },
          ),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.black),
            title: const Text('My orders'),
            onTap: () {
              Navigator.pop(context);
              // Navigate to orders screen
              // Navigator.pushNamed(context, '/orders');
            },
          ),
          ListTile(
            leading: const Icon(Icons.local_offer, color: Colors.black),
            title: const Text('Promo'),
            onTap: () {
              Navigator.pop(context);
              // Navigate to promo screen
              // Navigator.pushNamed(context, '/promo');
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color:Colors.black),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              // Navigate to settings screen
              // Navigator.pushNamed(context, '/settings');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.red),
            title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
            onTap: onSignOut, // Use onSignOut function for logout
          ),
        ],
      ),
    );
  }
}
