import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/avatar_presets.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/widgets/karlshare_avatar.dart';
import '../../../core/widgets/karlshare_button.dart';
import '../../../core/widgets/karlshare_input.dart';
import '../../../providers/user_provider.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameController = TextEditingController(text: 'My Phone');
  int _avatar = 0;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final name = _nameController.text.trim().isEmpty
        ? 'My Phone'
        : _nameController.text.trim();
    await ref
        .read(userProfileProvider.notifier)
        .save(displayName: name, avatarIndex: _avatar);
    if (mounted) context.go(RoutePaths.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: context.pop,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Make it yours',
                  style: Theme.of(context).textTheme.displayMedium),
              const SizedBox(height: AppConstants.space8),
              Text('Pick an avatar and a name nearby friends will see.',
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: AppConstants.space32),
              Expanded(
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: AppConstants.space16,
                    crossAxisSpacing: AppConstants.space16,
                  ),
                  itemCount: AvatarPresets.count,
                  itemBuilder: (context, i) {
                    final selected = i == _avatar;
                    return GestureDetector(
                      onTap: () => setState(() => _avatar = i),
                      child: AnimatedScale(
                        scale: selected ? 1.0 : 0.86,
                        duration: AppConstants.microInteraction,
                        curve: AppConstants.easeOutKarlshare,
                        child: Opacity(
                          opacity: selected ? 1 : 0.55,
                          child: KarlshareAvatar(
                            icon: AvatarPresets.byIndex(i),
                            size: 64,
                            borderWidth: selected ? 3 : 1.5,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppConstants.space16),
              Text('Display name',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: AppConstants.space8),
              KarlshareInput(
                controller: _nameController,
                hintText: 'Your name',
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppConstants.space24),
              KarlshareButton(label: 'Start Sharing', onPressed: _finish),
            ],
          ),
        ),
      ),
    );
  }
}
