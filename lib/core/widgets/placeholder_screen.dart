import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_constants.dart';
import 'gradient_text.dart';

/// Temporary scaffold used by routes whose real UI ships in Phase 2.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    this.next,
    this.nextLabel,
  });

  final String title;

  /// Optional route to navigate to via a CTA, for walking the flow in Phase 1.
  final String? next;
  final String? nextLabel;

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    return Scaffold(
      appBar: AppBar(
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: context.pop,
              )
            : null,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GradientText(title, style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: AppConstants.space12),
            Text(
              'Coming in Phase 2',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (next != null) ...[
              const SizedBox(height: AppConstants.space32),
              FilledButton(
                onPressed: () => context.go(next!),
                child: Text(nextLabel ?? 'Continue'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
