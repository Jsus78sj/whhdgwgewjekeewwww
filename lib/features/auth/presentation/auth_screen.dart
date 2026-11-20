import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/nexus_colors.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../../core/widgets/nexus_toast.dart';
import '../domain/github_account.dart';
import 'auth_controller.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _tokenController = TextEditingController();
  bool _obscureToken = true;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _submitToken() async {
    FocusScope.of(context).unfocus();
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      showNexusToast(
        context,
        'يرجى إدخال GitHub Personal Access Token أولاً',
        type: NexusToastType.warning,
      );
      return;
    }

    final ok = await ref
        .read(authControllerProvider.notifier)
        .connectWithToken(token);

    if (!mounted) return;
    if (ok) {
      final login = ref.read(authControllerProvider).activeAccount?.user.login;
      showNexusToast(
        context,
        'مرحباً @$login — تم الاتصال بنجاح',
        type: NexusToastType.success,
      );
    } else {
      final err = ref.read(authControllerProvider).errorMessage;
      showNexusToast(
        context,
        err ?? 'فشل الاتصال بـ GitHub',
        type: NexusToastType.error,
      );
    }
  }

  Future<void> _quickSwitch(SavedAccount account) async {
    final ok = await ref
        .read(authControllerProvider.notifier)
        .switchAccount(account);
    if (!mounted) return;
    if (ok) {
      showNexusToast(
        context,
        'تم الدخول بحساب @${account.user.login}',
        type: NexusToastType.success,
      );
    } else {
      final err = ref.read(authControllerProvider).errorMessage;
      showNexusToast(
        context,
        err ?? 'تعذر استعادة الحساب',
        type: NexusToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isBusy = authState.status == AuthStatus.authenticating;

    return Scaffold(
      body: NexusAmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              _AuthHeaderBar(),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GlassPanel(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          NexusColors.primary.withOpacity(0.22),
                                          NexusColors.indigo.withOpacity(0.22),
                                        ],
                                      ),
                                      border: Border.all(
                                        color: NexusColors.primary
                                            .withOpacity(0.32),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.vpn_key_rounded,
                                      size: 30,
                                      color: NexusColors.primarySoft,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                const Text(
                                  'Welcome back',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w700,
                                    color: NexusColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'أدخل رمز الوصول الشخصي (GitHub PAT) للاتصال المشفّر بحسابك',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: NexusColors.textMuted,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                const Padding(
                                  padding: EdgeInsets.only(left: 4, bottom: 8),
                                  child: Text(
                                    'Personal Access Token',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: NexusColors.textMuted,
                                    ),
                                  ),
                                ),
                                TextField(
                                  controller: _tokenController,
                                  obscureText: _obscureToken,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submitToken(),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13.5,
                                    letterSpacing: 0.6,
                                    color: NexusColors.textPrimary,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'ghp_xxxxxxxxxxxxxx',
                                    hintStyle: const TextStyle(
                                      fontFamily: 'monospace',
                                      color: NexusColors.textSubtle,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: _obscureToken
                                          ? 'إظهار التوكن'
                                          : 'إخفاء التوكن',
                                      onPressed: () {
                                        setState(() {
                                          _obscureToken = !_obscureToken;
                                        });
                                      },
                                      icon: Icon(
                                        _obscureToken
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: NexusColors.textSubtle,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.shield_outlined,
                                      size: 14,
                                      color: NexusColors.textSubtle,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: RichText(
                                        text: const TextSpan(
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: NexusColors.textSubtle,
                                          ),
                                          children: [
                                            TextSpan(text: 'يتطلب صلاحية '),
                                            TextSpan(
                                              text: 'repo',
                                              style: TextStyle(
                                                fontFamily: 'monospace',
                                                color: NexusColors.primarySoft,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            TextSpan(
                                              text:
                                                  ' • يُحفظ مشفّراً داخل Android Keystore',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (authState.errorMessage != null) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          NexusColors.rose.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            NexusColors.rose.withOpacity(0.32),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.error_outline_rounded,
                                          size: 18,
                                          color: NexusColors.roseSoft,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            authState.errorMessage!,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              color: NexusColors.roseSoft,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                NexusGradientButton(
                                  onPressed: isBusy ? null : _submitToken,
                                  child: isBusy
                                      ? const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                color: Colors.white,
                                              ),
                                            ),
                                            SizedBox(width: 10),
                                            Text('جارٍ التحقق والاتصال...'),
                                          ],
                                        )
                                      : const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.bolt_rounded, size: 19),
                                            SizedBox(width: 8),
                                            Text('Connect to GitHub'),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                          if (authState.savedAccounts.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            GlassPanel(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.switch_account_rounded,
                                        size: 17,
                                        color: NexusColors.primarySoft,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'الحسابات المحفوظة (${authState.savedAccounts.length})',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: NexusColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  for (final acc in authState.savedAccounts)
                                    _SavedAccountTile(
                                      account: acc,
                                      disabled: isBusy,
                                      onTap: () => _quickSwitch(acc),
                                      onDelete: () => ref
                                          .read(authControllerProvider.notifier)
                                          .removeSavedAccount(acc.id),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthHeaderBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: NexusColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: NexusColors.brandLogoGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: NexusColors.primary.withOpacity(0.42),
                  blurRadius: 16,
                ),
              ],
            ),
            child: const Icon(
              Icons.hub_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GitHub Nexus',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: NexusColors.textPrimary,
                ),
              ),
              Text(
                'REPO MANAGER PRO',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                  color: NexusColors.textSubtle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SavedAccountTile extends StatelessWidget {
  final SavedAccount account;
  final bool disabled;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SavedAccountTile({
    required this.account,
    required this.disabled,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: NexusColors.bgElevated.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NexusColors.borderSubtle),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: NexusColors.bgHover,
                  backgroundImage: account.user.avatarUrl.isNotEmpty
                      ? NetworkImage(account.user.avatarUrl)
                      : null,
                  child: account.user.avatarUrl.isEmpty
                      ? const Icon(Icons.person_rounded, size: 18)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: NexusColors.textPrimary,
                        ),
                      ),
                      Text(
                        '@${account.user.login} • ${account.maskedToken}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: NexusColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'حذف الحساب المحفوظ',
                  onPressed: disabled ? null : onDelete,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: NexusColors.roseSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
