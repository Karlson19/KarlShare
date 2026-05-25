import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/gradient_text.dart';
import '../../../core/widgets/karlshare_button.dart';
import '../widgets/connection_hero.dart';

/// Intro flow: Welcome + Why Karlshare as a 2-page swipe (Section 6.2).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 0) {
      _controller.nextPage(
        duration: AppConstants.transition,
        curve: AppConstants.easeOutKarlshare,
      );
    } else {
      context.go(RoutePaths.permissions);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.go(RoutePaths.permissions),
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [_WelcomePage(), _WhyPage()],
              ),
            ),
            _Dots(count: 2, active: _page),
            const SizedBox(height: AppConstants.space24),
            Padding(
              padding: const EdgeInsets.all(AppConstants.space24),
              child: KarlshareButton(
                label: _page == 0 ? 'Get Started' : 'Continue',
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.space24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ConnectionHero(),
          const SizedBox(height: AppConstants.space48),
          GradientText(
            'Share files at lightspeed',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displayMedium,
          ),
          const SizedBox(height: AppConstants.space16),
          Text(
            'No internet. No data. No limits.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _WhyPage extends StatelessWidget {
  const _WhyPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.space24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _Feature(
            icon: Icons.bolt_rounded,
            title: '5x faster than the rest',
            subtitle: 'Multi-threaded transfers over 5GHz WiFi Direct.',
          ),
          SizedBox(height: AppConstants.space32),
          _Feature(
            icon: Icons.lock_rounded,
            title: 'End-to-end encrypted',
            subtitle: 'TLS 1.3 on every transfer. Your files stay yours.',
          ),
          SizedBox(height: AppConstants.space32),
          _Feature(
            icon: Icons.public_rounded,
            title: 'Made in Ghana for the world',
            subtitle: 'World-class software, proudly African DNA.',
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: AppGradients.signature,
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
        const SizedBox(width: AppConstants.space16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppConstants.space4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: AppConstants.microInteraction,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == active ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == active ? colors.accent : colors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
