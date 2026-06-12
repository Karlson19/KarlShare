import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/route_paths.dart';
import '../../../core/router/app_router.dart';
import '../../../models/enums.dart';
import '../../../models/transfer.dart';
import '../providers/transfer_provider.dart';

/// One place that owns "a transfer just came in — make the user see it."
///
/// Mounted ABOVE every route (in the MaterialApp builder), so it surfaces an
/// incoming transfer no matter what screen the user is on: home, the file
/// picker, settings, or — the bug this fixes — the "Sent!" success screen
/// after sending. Previously each screen listened for itself, so screens that
/// weren't listening let a received file land silently on disk while the UI
/// sat frozen on a stale state. Centralising it kills that whole bug class.
class IncomingTransferWatcher extends ConsumerWidget {
  const IncomingTransferWatcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<TransferSession>(transferSessionProvider, (prev, next) {
      final before = prev?.transfers ?? const <String, Transfer>{};
      for (final t in next.transfers.values) {
        // Only act on the single frame a received transfer first appears.
        if (before.containsKey(t.id)) continue;
        if (t.direction != TransferDirection.received) continue;

        // If the live transfer screen is already open it shows the new
        // transfer in its session list — don't stack a second copy.
        final path = appRouter.routerDelegate.currentConfiguration.uri.path;
        if (path != RoutePaths.transfer) {
          appRouter.push(RoutePaths.transfer);
        }
        break; // one push is enough for a batch of new transfers
      }
    });
    return child;
  }
}
