import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_gradients.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/karlshare_button.dart';
import '../../../models/enums.dart';
import '../../../models/transfer_file.dart';
import '../../transfer/providers/transfer_provider.dart';
import '../providers/documents_provider.dart';
import '../providers/file_selection_provider.dart';
import '../providers/installed_apps_provider.dart';
import '../providers/media_library_provider.dart';
import '../widgets/file_list_tile.dart';
import '../widgets/photo_grid.dart';

class FilePickerScreen extends ConsumerStatefulWidget {
  const FilePickerScreen({super.key});

  @override
  ConsumerState<FilePickerScreen> createState() => _FilePickerScreenState();
}

class _FilePickerScreenState extends ConsumerState<FilePickerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: _order.length, vsync: this);

  // Tab order per Section 6.4.
  static const _order = [
    KFileType.image,
    KFileType.video,
    KFileType.app,
    KFileType.document,
    KFileType.audio,
  ];

  @override
  void initState() {
    super.initState();
    // Kick off the media permission flow as soon as the picker opens — the
    // first tab needs gallery access.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestMediaPermission(ref);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _send() {
    final selection = ref.read(fileSelectionProvider.notifier);
    if (selection.files.isEmpty) return;
    ref.read(selectedFilesProvider.notifier).state = selection.files;
    context.push(RoutePaths.transfer);
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(fileSelectionProvider);
    final selectionApi = ref.read(fileSelectionProvider.notifier);
    final count = selected.length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: context.pop,
        ),
        title: const Text('Select Files'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final t in _order) Tab(text: _tabLabel(t)),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabs,
            children: [
              for (final type in _order)
                _buildTab(type, selectionApi.isSelected, (f) {
                  HapticFeedback.selectionClick();
                  selectionApi.toggle(f);
                }),
            ],
          ),
          if (count > 0)
            Positioned(
              left: AppConstants.space16,
              right: AppConstants.space16,
              // Lift above the system navigation bar / gesture pill so the
              // gradient Send bar never blends into the OS nav buttons.
              bottom: AppConstants.space16 +
                  MediaQuery.viewPaddingOf(context).bottom,
              child: _SummaryCard(
                count: count,
                bytes: selectionApi.totalBytes,
                onSend: _send,
              ),
            ),
        ],
      ),
    );
  }

  static String _tabLabel(KFileType t) => switch (t) {
        KFileType.image => 'Photos',
        KFileType.video => 'Videos',
        KFileType.app => 'Apps',
        KFileType.document => 'Files',
        KFileType.audio => 'Music',
        KFileType.other => 'Other',
      };

  Widget _buildTab(
    KFileType type,
    bool Function(String) isSelected,
    void Function(TransferFile) onToggle,
  ) {
    switch (type) {
      case KFileType.image:
      case KFileType.video:
      case KFileType.audio:
        return _MediaTab(type: type, isSelected: isSelected, onToggle: onToggle);
      case KFileType.document:
        return _DocumentsTab(isSelected: isSelected, onToggle: onToggle);
      case KFileType.app:
        return _AppsTab(isSelected: isSelected, onToggle: onToggle);
      case KFileType.other:
        return const SizedBox.shrink();
    }
  }
}

// ---- Photos / Videos / Audio (photo_manager) -------------------------------

class _MediaTab extends ConsumerWidget {
  const _MediaTab({
    required this.type,
    required this.isSelected,
    required this.onToggle,
  });

  final KFileType type;
  final bool Function(String) isSelected;
  final void Function(TransferFile) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(mediaPermissionProvider);
    if (permission == MediaPermissionState.denied) {
      return _MediaPermissionPrompt(
        onRetry: () => requestMediaPermission(ref),
      );
    }
    if (permission == MediaPermissionState.unsupported) {
      return const _Centered(
        message:
            "Gallery access isn't available on this platform.\nInstall on Android to share photos, videos and music.",
      );
    }
    if (permission == MediaPermissionState.unknown) {
      return const _Centered.loading();
    }

    final assetsAsync = ref.watch(mediaAssetsProvider(type));
    return assetsAsync.when(
      loading: () => const _Centered.loading(),
      error: (e, _) => _Centered(message: "Couldn't load media:\n$e"),
      data: (assets) {
        if (assets.isEmpty) {
          return _Centered(message: _emptyLabel(type));
        }
        // Audio gets a list view; photos & videos go to the grid.
        if (type == KFileType.audio) {
          return ListView.builder(
            padding: const EdgeInsets.only(
                top: AppConstants.space8, bottom: 120),
            itemCount: assets.length,
            itemBuilder: (context, i) {
              final file = assets[i].file;
              return FileListTile(
                file: file,
                selected: isSelected(file.id),
                onToggle: () => onToggle(file),
              );
            },
          );
        }
        return PhotoGrid(
          assets: assets,
          isSelected: isSelected,
          onToggle: onToggle,
        );
      },
    );
  }

  static String _emptyLabel(KFileType type) => switch (type) {
        KFileType.image => 'No photos on this device yet.',
        KFileType.video => 'No videos on this device yet.',
        KFileType.audio => 'No music on this device yet.',
        _ => 'Nothing to show.',
      };
}

class _MediaPermissionPrompt extends StatelessWidget {
  const _MediaPermissionPrompt({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 56, color: colors.textTertiary),
            const SizedBox(height: AppConstants.space16),
            Text(
              "Karlshare needs access to your gallery to send photos, videos and music.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppConstants.space24),
            SizedBox(
              width: 220,
              child: KarlshareButton(
                label: 'Grant access',
                onPressed: onRetry,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Documents (system file picker) ----------------------------------------

class _DocumentsTab extends ConsumerWidget {
  const _DocumentsTab({required this.isSelected, required this.onToggle});

  final bool Function(String) isSelected;
  final void Function(TransferFile) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentBrowserProvider);
    final controller = ref.read(documentBrowserProvider.notifier);
    final colors = Theme.of(context).extension<KarlshareColors>()!;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(AppConstants.space16),
          sliver: SliverToBoxAdapter(
            child: KarlshareButton(
              label: 'Browse files',
              icon: Icons.folder_open_rounded,
              variant: KarlshareButtonVariant.secondary,
              onPressed: () async {
                final picks = await controller.pickFiles();
                for (final p in picks) {
                  if (!isSelected(p.id)) onToggle(p);
                }
              },
            ),
          ),
        ),
        if (docs.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.space24),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.description_outlined,
                        size: 56, color: colors.textTertiary),
                    const SizedBox(height: AppConstants.space12),
                    Text(
                      "Tap Browse files to pick documents from anywhere on your device.",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 120),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final file = docs[i];
                  return FileListTile(
                    file: file,
                    selected: isSelected(file.id),
                    onToggle: () => onToggle(file),
                  );
                },
                childCount: docs.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ---- Installed apps (Android native) ---------------------------------------

class _AppsTab extends ConsumerWidget {
  const _AppsTab({required this.isSelected, required this.onToggle});

  final bool Function(String) isSelected;
  final void Function(TransferFile) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appsAsync = ref.watch(installedAppsProvider);
    return appsAsync.when(
      loading: () => const _Centered.loading(),
      error: (e, _) => _Centered(message: "Couldn't list apps:\n$e"),
      data: (apps) {
        if (apps.isEmpty) {
          return const _Centered(
            message:
                "App sharing is Android-only.\nInstall on Android to share APKs.",
          );
        }
        final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            AppConstants.space16,
            AppConstants.space16,
            AppConstants.space16,
            120 + bottomInset,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: AppConstants.space20,
            crossAxisSpacing: AppConstants.space12,
            childAspectRatio: 0.70,
          ),
          itemCount: apps.length,
          itemBuilder: (context, i) {
            final app = apps[i];
            final file = app.toTransferFile();
            return _AppTile(
              app: app,
              selected: isSelected(file.id),
              onTap: () => onToggle(file),
            );
          },
        );
      },
    );
  }
}

/// One app in the Apps grid: real launcher icon, name and size, Xender-style.
class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.selected, required this.onTap});

  final InstalledApp app;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: AppConstants.microInteraction,
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSmall + 4),
                  border: Border.all(
                    color: selected ? colors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                padding: const EdgeInsets.all(2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSmall + 2),
                  child: app.iconBytes != null
                      ? Image.memory(app.iconBytes!, width: 52, height: 52,
                          fit: BoxFit.cover, gaplessPlayback: true)
                      : Container(
                          color: colors.accentSoft,
                          child: Icon(Icons.android, color: colors.accent),
                        ),
                ),
              ),
              if (selected)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.background, width: 2),
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.space8),
          Text(
            app.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                  height: 1.15,
                  fontSize: 12,
                ),
          ),
          Text(
            FormatUtils.fileSize(app.sizeBytes),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: colors.textTertiary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ---- Shared bits -----------------------------------------------------------

class _Centered extends StatelessWidget {
  const _Centered({required this.message}) : loading = false;
  const _Centered.loading()
      : message = null,
        loading = true;

  final String? message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.space24),
        child: Text(
          message ?? '',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.count,
    required this.bytes,
    required this.onSend,
  });

  final int count;
  final int bytes;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSend,
      child: Container(
        height: AppConstants.buttonHeightPrimary,
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.space20),
        decoration: BoxDecoration(
          gradient: AppGradients.signature,
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          boxShadow: [
            BoxShadow(
              color: AppColors.electricPurple.withValues(alpha: 0.30),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$count selected · ${FormatUtils.fileSize(bytes)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            const Text(
              'Send',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

