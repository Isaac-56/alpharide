import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import 'account_ui.dart';

class FeedbackTopicScreen extends StatelessWidget {
  final FirebaseAuth auth;
  final FirestoreService firestoreService;

  const FeedbackTopicScreen({
    super.key,
    required this.auth,
    required this.firestoreService,
  });

  static const List<_FeedbackTopic> _topics = <_FeedbackTopic>[
    _FeedbackTopic(
      label: 'Something is not working',
      icon: Icons.build_circle_outlined,
    ),
    _FeedbackTopic(
      label: 'App missing a feature',
      icon: Icons.extension_outlined,
    ),
    _FeedbackTopic(
      label: 'Inconvenient interface',
      icon: Icons.touch_app_outlined,
    ),
    _FeedbackTopic(
      label: 'I want to propose an idea',
      icon: Icons.lightbulb_outline_rounded,
    ),
    _FeedbackTopic(
      label: 'Other',
      icon: Icons.chat_bubble_outline_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'Choose a topic',
      child: Column(
        children: _topics.asMap().entries.map(
          (MapEntry<int, _FeedbackTopic> entry) {
            final _FeedbackTopic topic = entry.value;

            return AlphaMenuTile(
              icon: topic.icon,
              title: topic.label,
              showDivider: entry.key != _topics.length - 1,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => FeedbackDetailScreen(
                    topic: topic.label,
                    auth: auth,
                    firestoreService: firestoreService,
                  ),
                ),
              ),
            );
          },
        ).toList(growable: false),
      ),
    );
  }
}

class FeedbackDetailScreen extends StatefulWidget {
  final String topic;
  final FirebaseAuth auth;
  final FirestoreService firestoreService;

  const FeedbackDetailScreen({
    super.key,
    required this.topic,
    required this.auth,
    required this.firestoreService,
  });

  @override
  State<FeedbackDetailScreen> createState() => _FeedbackDetailScreenState();
}

class _FeedbackDetailScreenState extends State<FeedbackDetailScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String message = _controller.text.trim();

    if (message.length < 3) {
      showAlphaMessage(
        context,
        'Please tell us a little more before sending.',
        error: true,
      );
      _focusNode.requestFocus();
      return;
    }

    final String? phoneNumber = widget.auth.currentUser?.phoneNumber;

    if (phoneNumber == null) {
      showAlphaMessage(
        context,
        'Please sign in again before sending feedback.',
        error: true,
      );
      return;
    }

    setState(() => _sending = true);

    try {
      await widget.firestoreService.submitFeedback(
        phoneNumber: phoneNumber,
        topic: widget.topic,
        message: message,
      );

      if (!mounted) return;

      Navigator.pushReplacement<void, void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const FeedbackThankYouScreen(),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      showAlphaMessage(
        context,
        'Your feedback could not be sent. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlphaPageScaffold(
      title: 'Tell us in detail',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AlphaColors.primary.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              widget.topic,
              style: const TextStyle(
                color: AlphaColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            minLines: 5,
            maxLines: 8,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(
              color: AlphaColors.text(context),
              fontSize: 16,
              height: 1.45,
            ),
            decoration: alphaInputDecoration(
              context,
              label: 'Your feedback',
              hint: 'Describe what happened or what you would improve...',
              prefixIcon: Icons.edit_note_rounded,
            ),
          ),
          const SizedBox(height: 18),
          AlphaPrimaryButton(
            label: 'Send feedback',
            icon: Icons.send_rounded,
            loading: _sending,
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}

class FeedbackThankYouScreen extends StatelessWidget {
  const FeedbackThankYouScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AlphaColors.background(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            children: <Widget>[
              const Spacer(),
              Container(
                width: 110,
                height: 110,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AlphaColors.primary.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.thumb_up_alt_rounded,
                  color: AlphaColors.primary,
                  size: 54,
                ),
              ),
              const SizedBox(height: 30),
              Text(
                'Thank you!',
                style: TextStyle(
                  color: AlphaColors.text(context),
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your feedback helps us make AlphaRide safer, simpler, and better for South Sudan.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AlphaColors.muted(context),
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const Spacer(),
              AlphaPrimaryButton(
                label: 'Done',
                onPressed: () => Navigator.of(context).popUntil(
                  (Route<dynamic> route) => route.isFirst,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackTopic {
  final String label;
  final IconData icon;

  const _FeedbackTopic({
    required this.label,
    required this.icon,
  });
}
