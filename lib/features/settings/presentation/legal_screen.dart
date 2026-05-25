import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

/// Simple scrollable text page used for the Privacy Policy and Terms.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.title, required this.blocks});

  final String title;

  /// Each entry is a (heading, body) pair. An empty heading renders body only.
  final List<(String, String)> blocks;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.space20,
          AppConstants.space16,
          AppConstants.space20,
          AppConstants.space48,
        ),
        children: [
          for (final (heading, body) in blocks) ...[
            if (heading.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                    top: AppConstants.space20, bottom: AppConstants.space8),
                child: Text(
                  heading,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: colors.textPrimary),
                ),
              ),
            Text(
              body,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.textSecondary,
                    height: 1.55,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalScreen(
      title: 'Privacy Policy',
      blocks: [
        (
          '',
          'Karlshare is built to share your files without sending them anywhere except the phone right next to you. This page explains what the app does and does not do with your information.'
        ),
        (
          'Your files',
          'When you send a file, it travels directly from your phone to the other phone over a local wireless link. It is never uploaded to us or to any server, and we never see, store, or have any access to it.'
        ),
        (
          'What we collect',
          'By default the app may collect anonymous usage counts, for example how many transfers happen, to help us fix problems and improve the app. This never includes your files, file names, contacts, or anything that identifies you personally. You can turn it off any time in Settings under Privacy.'
        ),
        (
          'Permissions',
          'The app asks for nearby devices, location, and storage access only so it can find phones around you and read the files you choose to send. These permissions are used on your device and nothing from them leaves your phone.'
        ),
        (
          'Children',
          'Karlshare does not target children and does not knowingly collect any personal data from anyone.'
        ),
        (
          'Contact',
          'Questions about privacy can be raised on the project page at github.com/Karlson19/KarlShare.'
        ),
      ],
    );
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalScreen(
      title: 'Terms of Use',
      blocks: [
        (
          '',
          'By using Karlshare you agree to these simple terms. They are written plainly on purpose.'
        ),
        (
          'Use it responsibly',
          'You are responsible for the files you send and receive. Only share content you have the right to share, and do not use the app to send anything illegal or harmful.'
        ),
        (
          'No warranty',
          'Karlshare is provided as is, free of charge. We work hard to make transfers fast and reliable, but we cannot promise it will work perfectly on every device or in every situation.'
        ),
        (
          'Your device, your data',
          'Because files move directly between phones and are never stored by us, keeping copies and backups of your important files remains your responsibility.'
        ),
        (
          'Changes',
          'The app will improve over time, and these terms may be updated alongside it. Continuing to use the app means you accept the current version.'
        ),
      ],
    );
  }
}
