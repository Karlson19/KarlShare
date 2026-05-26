import 'package:go_router/go_router.dart';
import '../constants/route_paths.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/onboarding/presentation/permissions_screen.dart';
import '../../features/onboarding/presentation/profile_setup_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/file_picker/presentation/file_picker_screen.dart';
import '../../features/transfer/presentation/transfer_screen.dart';
import '../../features/transfer/presentation/transfer_complete_screen.dart';
import '../../features/transfer/presentation/receive_screen.dart';
import '../../features/transfer/presentation/send_connect_screen.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/legal_screen.dart';
import '../../features/qr_pair/presentation/qr_pair_screen.dart';

final appRouter = GoRouter(
  initialLocation: RoutePaths.splash,
  routes: [
    GoRoute(
      path: RoutePaths.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: RoutePaths.onboarding,
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: RoutePaths.permissions,
      builder: (context, state) => const PermissionsScreen(),
    ),
    GoRoute(
      path: RoutePaths.profileSetup,
      builder: (context, state) => const ProfileSetupScreen(),
    ),
    GoRoute(
      path: RoutePaths.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: RoutePaths.filePicker,
      builder: (context, state) => const FilePickerScreen(),
    ),
    GoRoute(
      path: RoutePaths.transfer,
      builder: (context, state) => const TransferScreen(),
    ),
    GoRoute(
      path: RoutePaths.transferComplete,
      builder: (context, state) => const TransferCompleteScreen(),
    ),
    GoRoute(
      path: RoutePaths.receive,
      builder: (context, state) => const ReceiveScreen(),
    ),
    GoRoute(
      path: RoutePaths.sendConnect,
      builder: (context, state) => const SendConnectScreen(),
    ),
    GoRoute(
      path: RoutePaths.history,
      builder: (context, state) => const HistoryScreen(),
    ),
    GoRoute(
      path: RoutePaths.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: RoutePaths.qrPair,
      builder: (context, state) => const QrPairScreen(),
    ),
    GoRoute(
      path: RoutePaths.privacy,
      builder: (context, state) => const PrivacyScreen(),
    ),
    GoRoute(
      path: RoutePaths.terms,
      builder: (context, state) => const TermsScreen(),
    ),
  ],
);
