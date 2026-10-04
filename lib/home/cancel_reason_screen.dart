import 'package:flutter/material.dart';

import '../account/account_ui.dart';

const Color primaryColor = Color(0xFF39FF14);

class CancelReasonScreen extends StatelessWidget {
  const CancelReasonScreen({super.key});

  static const Color primaryColor = Color(0xFF39FF14);

  static const List<String> reasons = <String>[
    'Fare is too high',
    'Just trying the app',
    'Changed my mind',
    'No driver assigned',
    'Pickup point is incorrect',
    'Custom reason',
  ];

  Future<void> _selectReason(BuildContext context, String reason) async {
    if (reason != 'Custom reason') {
      Navigator.pop(context, reason);
      return;
    }

    final String? customReason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AlphaColors.background(context),
      builder: (_) => const _CustomCancellationReasonSheet(),
    );

    if (customReason == null || !context.mounted) return;
    Navigator.pop(context, customReason);
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = AlphaColors.background(context);
    final Color surfaceColor = AlphaColors.surface(context);
    final Color textColor = AlphaColors.text(context);
    final Color mutedColor = AlphaColors.muted(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: surfaceColor,
                shape: CircleBorder(
                  side: BorderSide(color: AlphaColors.border(context)),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  child: SizedBox(
                    width: AlphaSpacing.controlHeight,
                    height: AlphaSpacing.controlHeight,
                    child: Icon(
                      Icons.close_rounded,
                      color: textColor,
                      size: 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 38),
              Text(
                'Cancel order',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 22),
              Expanded(
                child: ListView.separated(
                  itemCount: reasons.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final String reason = reasons[index];

                    return Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () => _selectReason(context, reason),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 17,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  reason,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: mutedColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: primaryColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Choose the reason that best describes your cancellation.',
                      style: TextStyle(
                        color: mutedColor,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomCancellationReasonSheet extends StatefulWidget {
  const _CustomCancellationReasonSheet();

  @override
  State<_CustomCancellationReasonSheet> createState() =>
      _CustomCancellationReasonSheetState();
}

class _CustomCancellationReasonSheetState
    extends State<_CustomCancellationReasonSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _canSubmit = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update(String value) {
    final bool canSubmit = value.trim().length >= 3;
    if (canSubmit != _canSubmit) setState(() => _canSubmit = canSubmit);
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets keyboard = MediaQuery.viewInsetsOf(context);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(22, 0, 22, 22 + keyboard.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Tell us why you are cancelling',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'A short explanation helps AlphaRide improve future requests.',
            style: TextStyle(color: AlphaColors.muted(context), height: 1.4),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const Key('customCancellationReasonField'),
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            onChanged: _update,
            onSubmitted: (_) => _submit(),
            decoration: alphaInputDecoration(
              context,
              label: 'Cancellation reason',
              hint: 'What made you cancel this ride?',
              prefixIcon: Icons.edit_note_rounded,
            ),
          ),
          const SizedBox(height: 12),
          AlphaPrimaryButton(
            label: 'Continue cancellation',
            icon: Icons.arrow_forward_rounded,
            onPressed: _canSubmit ? _submit : null,
          ),
        ],
      ),
    );
  }
}
