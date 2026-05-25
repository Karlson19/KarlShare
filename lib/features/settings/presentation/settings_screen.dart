import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/avatar_presets.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/karlshare_avatar.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/user_provider.dart';
import '../../history/providers/history_provider.dart';
import '../../transfer/providers/transfer_provider.dart';

/// Settings (Section 6.7). Grouped cards with monochrome accent icons and
/// a hairline-bordered row hierarchy. Premium upsell intentionally absent —
/// Karlshare v1 ships fully free (see feedback memo `no-pro-tier`).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.space16,
          AppConstants.space8,
          AppConstants.space16,
          AppConstants.space32,
        ),
        children: [
          _ProfileCard(
            name: profile?.displayName ?? 'Set your name',
            avatarIndex: profile?.avatarIndex ?? 0,
            onEdit: () => context.push(RoutePaths.profileSetup),
          ),
          const SizedBox(height: AppConstants.space24),
          const _SectionHeader(label: 'Appearance'),
          _SettingsGroup(
            children: [
              _ThemeRow(value: themeMode, ref: ref),
              const _SettingsDivider(),
              _SettingsRow(
                icon: Icons.language_rounded,
                label: 'Language',
                trailing: const _ValuePill(text: 'English'),
                onTap: null,
              ),
            ],
          ),
          const SizedBox(height: AppConstants.space24),
          const _SectionHeader(label: 'Transfer'),
          _SettingsGroup(
            children: [
              _SettingsRow(
                icon: Icons.folder_open_rounded,
                label: 'Received files are saved to',
                trailing: const _ValuePill(text: 'Karlshare/'),
                onTap: null,
              ),
            ],
          ),
          const SizedBox(height: AppConstants.space24),
          const _SectionHeader(label: 'Privacy'),
          _SettingsGroup(
            children: [
              _ToggleRow(
                icon: Icons.insights_rounded,
                label: 'Share anonymous analytics',
                value: ref.watch(analyticsEnabledProvider),
                onChanged: (v) =>
                    ref.read(analyticsEnabledProvider.notifier).set(v),
              ),
              const _SettingsDivider(),
              _SettingsRow(
                icon: Icons.history_toggle_off_rounded,
                label: 'Clear history',
                onTap: () => _confirmClearHistory(context, ref),
              ),
              const _SettingsDivider(),
              _SettingsRow(
                icon: Icons.devices_other_rounded,
                label: 'Reset paired devices',
                onTap: () => _confirmResetPaired(context, ref),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.space24),
          const _SectionHeader(label: 'About'),
          _SettingsGroup(
            children: [
              _SettingsRow(
                icon: Icons.info_outline_rounded,
                label: 'Version',
                trailing: const _ValuePill(text: '1.0.0'),
                onTap: null,
              ),
              const _SettingsDivider(),
              _SettingsRow(
                icon: Icons.favorite_rounded,
                label: 'Built by Karlshare · Ghana',
                onTap: null,
              ),
              const _SettingsDivider(),
              _SettingsRow(
                icon: Icons.policy_outlined,
                label: 'Privacy Policy',
                onTap: () => context.push(RoutePaths.privacy),
              ),
              const _SettingsDivider(),
              _SettingsRow(
                icon: Icons.description_outlined,
                label: 'Terms',
                onTap: () => context.push(RoutePaths.terms),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmResetPaired(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset paired devices?'),
        content: const Text(
            'Karlshare will forget every device it has trusted before. They will be treated as new the next time you connect.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(transferServiceProvider).forgetAllPeers();
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Paired devices reset')),
              );
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _confirmClearHistory(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
            "Your transfer log will be wiped. Files themselves stay put."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(historyProvider.notifier).clear();
              Navigator.of(ctx).pop();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space12,
        AppConstants.space8,
        AppConstants.space12,
        AppConstants.space8,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.textTertiary,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        border: Border.all(color: colors.border, width: 1),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return Padding(
      padding: const EdgeInsets.only(left: 56),
      child: Divider(height: 1, color: colors.border),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.space16),
          child: Row(
            children: [
              _IconBubble(icon: icon, colors: colors),
              const SizedBox(width: AppConstants.space12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                      ),
                ),
              ),
              ?trailing,
              if (onTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: AppConstants.space8),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: colors.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.space16),
        child: Row(
          children: [
            _IconBubble(icon: icon, colors: colors),
            const SizedBox(width: AppConstants.space12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                    ),
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Subtle accent-tinted icon container — the v1 redesign retired the
/// gradient-shader icon (felt heavy at row-icon size).
class _IconBubble extends StatelessWidget {
  const _IconBubble({required this.icon, required this.colors});

  final IconData icon;
  final KarlshareColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
      ),
      child: Icon(icon, size: 18, color: colors.accent),
    );
  }
}

class _ValuePill extends StatelessWidget {
  const _ValuePill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: colors.textSecondary),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.value, required this.ref});

  final ThemeMode value;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.space16),
        child: Row(
          children: [
            _IconBubble(icon: Icons.contrast_rounded, colors: colors),
            const SizedBox(width: AppConstants.space12),
            Expanded(
              child: Text(
                'Theme',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                    ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppConstants.radiusPill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final mode in ThemeMode.values)
                    _ThemeChip(
                      label: switch (mode) {
                        ThemeMode.system => 'Auto',
                        ThemeMode.light => 'Light',
                        ThemeMode.dark => 'Dark',
                      },
                      selected: mode == value,
                      onTap: () =>
                          ref.read(themeModeProvider.notifier).setMode(mode),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.microInteraction,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.surfaceElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusPill),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.textPrimary : colors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.avatarIndex,
    required this.onEdit,
  });

  final String name;
  final int avatarIndex;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        child: Container(
          padding: const EdgeInsets.all(AppConstants.space16),
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
            border: Border.all(color: colors.border, width: 1),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            children: [
              KarlshareAvatar(
                icon: AvatarPresets.byIndex(avatarIndex),
                size: 56,
              ),
              const SizedBox(width: AppConstants.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: colors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to edit your profile',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
