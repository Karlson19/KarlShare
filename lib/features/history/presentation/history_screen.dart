import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/karlshare_button.dart';
import '../../../core/widgets/kente_pattern.dart';
import '../../../models/enums.dart';
import '../../../models/transfer.dart';
import '../providers/history_provider.dart';
import '../widgets/history_tile.dart';

/// Live search query for the history lists (file or device names).
final _historySearchProvider =
    StateProvider.autoDispose<String>((ref) => '');

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _confirmClear() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text("Your transfer log will be wiped. Files themselves stay put."),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Sent'),
            Tab(text: 'Received'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _confirmClear,
            tooltip: 'Clear history',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.space16,
              AppConstants.space12,
              AppConstants.space16,
              0,
            ),
            child: TextField(
              onChanged: (q) =>
                  ref.read(_historySearchProvider.notifier).state = q,
              decoration: const InputDecoration(
                hintText: 'Search files or devices',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.all(Radius.circular(AppConstants.radiusSmall)),
                ),
              ),
            ),
          ),
          const _StorageSummary(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _HistoryList(direction: TransferDirection.sent),
                _HistoryList(direction: TransferDirection.received),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Totals across the whole log: how much has moved through Karlshare.
class _StorageSummary extends ConsumerWidget {
  const _StorageSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(historyProvider);
    if (all.isEmpty) return const SizedBox.shrink();
    var sentBytes = 0;
    var receivedBytes = 0;
    for (final t in all) {
      if (t.direction == TransferDirection.sent) {
        sentBytes += t.totalBytes;
      } else {
        receivedBytes += t.totalBytes;
      }
    }
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space20,
        AppConstants.space8,
        AppConstants.space20,
        AppConstants.space4,
      ),
      child: Row(
        children: [
          Text(
            '${all.length} transfers',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: colors.textSecondary),
          ),
          const Spacer(),
          Icon(Icons.north_east_rounded, size: 12, color: AppColors.gold),
          Text(
            ' ${FormatUtils.fileSize(sentBytes)}   ',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: colors.textSecondary),
          ),
          Icon(Icons.south_west_rounded, size: 12, color: AppColors.forest),
          Text(
            ' ${FormatUtils.fileSize(receivedBytes)}',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.direction});

  final TransferDirection direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var transfers = ref.watch(historyByDirectionProvider(direction));
    final query = ref.watch(_historySearchProvider).trim().toLowerCase();
    if (query.isNotEmpty) {
      transfers = transfers
          .where((t) =>
              t.device.name.toLowerCase().contains(query) ||
              t.files.any((f) => f.name.toLowerCase().contains(query)))
          .toList();
    }
    if (transfers.isEmpty && query.isNotEmpty) {
      return Center(
        child: Text(
          'Nothing matches "$query".',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    if (transfers.isEmpty) return _EmptyState(direction: direction);

    final grouped = <String, List<Transfer>>{};
    for (final t in transfers) {
      grouped.putIfAbsent(FormatUtils.dateGroup(t.timestamp), () => []).add(t);
    }
    // Preserve canonical order regardless of map insertion.
    const order = ['Today', 'Yesterday', 'This Week', 'Earlier'];
    final sections = [
      for (final s in order)
        if (grouped[s] != null) MapEntry(s, grouped[s]!),
    ];

    final colors = Theme.of(context).extension<KarlshareColors>()!;

    return ListView.builder(
      padding: const EdgeInsets.all(AppConstants.space16),
      itemCount: sections.length,
      itemBuilder: (context, i) {
        final entry = sections[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (i > 0) const SizedBox(height: AppConstants.space16),
            Padding(
              padding: const EdgeInsets.only(
                left: AppConstants.space4,
                bottom: AppConstants.space8,
              ),
              child: Text(
                entry.key.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      letterSpacing: 1.2,
                    ),
              ),
            ),
            for (final t in entry.value) ...[
              Dismissible(
                key: ValueKey(t.id),
                direction: DismissDirection.endToStart,
                background: _SwipeBackground(),
                onDismissed: (_) =>
                    ref.read(historyProvider.notifier).remove(t.id),
                child: HistoryTile(transfer: t),
              ),
              const SizedBox(height: AppConstants.space8),
            ],
          ],
        );
      },
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.space24),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.direction});

  final TransferDirection direction;

  @override
  Widget build(BuildContext context) {
    final isSent = direction == TransferDirection.sent;
    return Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(child: KentePattern(opacity: 0.05, cell: 64)),
        ),
        Padding(
          padding: const EdgeInsets.all(AppConstants.space24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _EmptyBasket(),
              const SizedBox(height: AppConstants.space24),
              Text(
                'No ${isSent ? "sent" : "received"} transfers yet.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppConstants.space8),
              Text(
                isSent
                    ? 'Make the first move.'
                    : 'Ask a friend to send you something.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppConstants.space24),
              SizedBox(
                width: 220,
                child: KarlshareButton(
                  label: isSent ? 'Send a File' : 'Go Home',
                  icon: isSent ? Icons.arrow_upward_rounded : Icons.home_rounded,
                  onPressed: () => context.go(
                    isSent ? RoutePaths.filePicker : RoutePaths.home,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyBasket extends StatelessWidget {
  const _EmptyBasket();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.ashantiGold.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.shopping_basket_outlined,
        size: 56,
        color: AppColors.ashantiGold,
      ),
    );
  }
}
