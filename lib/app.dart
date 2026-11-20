import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/nexus_colors.dart';
import 'core/theme/nexus_theme.dart';
import 'core/widgets/glass_panel.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/shell/presentation/workspace_shell_screen.dart';

class GitHubNexusApp extends ConsumerWidget {
  const GitHubNexusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return MaterialApp(
      title: 'GitHub Nexus',
      debugShowCheckedModeBanner: false,
      theme: NexusTheme.dark,
      home: switch (authState.status) {
        AuthStatus.initializing => const _SessionBootstrapView(),
        AuthStatus.authenticated => const WorkspaceShellScreen(),
        AuthStatus.unauthenticated ||
        AuthStatus.authenticating =>
          const AuthScreen(),
      },
    );
  }
}

class _SessionBootstrapView extends StatelessWidget {
  const _SessionBootstrapView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NexusAmbientBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: NexusColors.brandLogoGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: NexusColors.primary.withOpacity(0.4),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.hub_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: NexusColors.primarySoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
