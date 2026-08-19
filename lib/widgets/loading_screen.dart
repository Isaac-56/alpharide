import 'package:flutter/material.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  static const Color _primaryColor = Color(0xFF39FF14);
  static const String _brandName = 'ALPHA RIDE';

  late final AnimationController _controller;
  late final Animation<double> _logoEntrance;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _logoEntrance = CurvedAnimation(
      parent: _controller,
      curve: const Interval(
        0,
        0.34,
        curve: Curves.easeOutCubic,
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _primaryColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (
            BuildContext context,
            BoxConstraints constraints,
          ) {
            final double logoSize =
                (constraints.maxWidth * 0.82).clamp(260.0, 370.0).toDouble();

            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FadeTransition(
                    opacity: _logoEntrance,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.86,
                        end: 1,
                      ).animate(_logoEntrance),
                      child: SizedBox.square(
                        dimension: logoSize,
                        child: Stack(
                          children: <Widget>[
                            Positioned.fill(
                              child: Image.asset(
                                'assets/images/logo.png',
                                cacheWidth: 800,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),

                            // Covers the word embedded in the PNG so it can
                            // be rebuilt below as independently animated
                            // letters. The rest of the logo stays unchanged.
                            Positioned(
                              left: logoSize * 0.225,
                              top: logoSize * 0.477,
                              width: logoSize * 0.55,
                              height: logoSize * 0.09,
                              child: const ColoredBox(
                                color: _primaryColor,
                              ),
                            ),

                            Positioned(
                              left: logoSize * 0.225,
                              top: logoSize * 0.487,
                              width: logoSize * 0.55,
                              height: logoSize * 0.07,
                              child: _AnimatedBrandName(
                                controller: _controller,
                                text: _brandName,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(0, -logoSize * 0.15),
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _controller,
                        curve: const Interval(
                          0.72,
                          1,
                          curve: Curves.easeOut,
                        ),
                      ),
                      child: const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AnimatedBrandName extends StatelessWidget {
  final AnimationController controller;
  final String text;

  const _AnimatedBrandName({
    required this.controller,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final List<String> characters = text.split('');

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(
          characters.length,
          (int index) {
            final String character = characters[index];
            final double start = 0.20 + (index * 0.055);
            final double end = (start + 0.24).clamp(0.0, 1.0).toDouble();
            final Animation<double> letterAnimation = CurvedAnimation(
              parent: controller,
              curve: Interval(
                start.clamp(0.0, 1.0).toDouble(),
                end,
                curve: Curves.easeOutBack,
              ),
            );

            if (character == ' ') {
              return const SizedBox(width: 8);
            }

            return AnimatedBuilder(
              animation: letterAnimation,
              builder: (
                BuildContext context,
                Widget? child,
              ) {
                final double value = letterAnimation.value;

                return Opacity(
                  opacity: value.clamp(0.0, 1.0).toDouble(),
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - value)),
                    child: Transform.scale(
                      scale: 0.72 + (0.28 * value),
                      child: child,
                    ),
                  ),
                );
              },
              child: Text(
                character,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 27,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
