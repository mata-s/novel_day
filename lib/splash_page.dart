import 'package:flutter/material.dart';
import 'auth_gate.dart';
import 'main.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // フェード: 0→1→0
    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
    ]).animate(_controller);

    // スケール: 0.96→1.0→1.02（少しだけ前に出て消える）
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.96, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.02)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 30,
      ),
    ]).animate(_controller);

    _controller.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) {
            return AuthGate(
              signedInBuilder: (context, session) {
                return SignedInRouter(session: session);
              },
            );
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // スプラッシュ側でフェードアウト済みなので、次画面はアニメーションなし
            return child;
          },
        ),
        (route) => false,
      );
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: cs.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ScaleTransition(
              scale: _scale,
              child: FadeTransition(
                opacity: _opacity,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    final iconSize = size.shortestSide * 0.8;

                    return Image.asset(
                      'assets/icon_opening.png',
                      width: iconSize,
                      height: iconSize,
                      fit: BoxFit.contain,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}