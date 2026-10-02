import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/state/auth_provider.dart';
import '../../../core/state/session_provider.dart';
import '../../../core/utils/join_code_helper.dart';
import '../member/member_presence_screen.dart';

class JoinSessionScreen extends StatefulWidget {
  final String? initialCode;

  const JoinSessionScreen({super.key, this.initialCode});

  @override
  State<JoinSessionScreen> createState() => _JoinSessionScreenState();
}

class _JoinSessionScreenState extends State<JoinSessionScreen> {
  late TextEditingController _codeController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.initialCode ?? '');
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _join(String code) async {
    final cleaned = JoinCodeHelper.normalize(code);
    if (cleaned.isEmpty) return;

    final sessionProvider = context.read<SessionProvider>();
    final authProvider = context.read<AuthProvider>();

    final user = authProvider.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication required to join a presence session.'),
            backgroundColor: AppColors.missing,
          ),
        );
      }
      return;
    }

    final success = await sessionProvider.joinSessionByCode(
      joinCode: cleaned,
      user: user,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Joined group presence check!'),
          backgroundColor: AppColors.present,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MemberPresenceScreen()),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sessionProvider.errorMessage ?? 'Could not join session.'),
          backgroundColor: AppColors.missing,
        ),
      );
    }
  }

  void _simulateQrScan() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.accent, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner_rounded, size: 70, color: AppColors.accent),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Camera Viewfinder',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Point your camera at an organizer\'s screen displaying the session QR code or paste clipboard invite link.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
                    final text = clipboard?.text?.trim() ?? '';
                    if (text.isNotEmpty) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      _codeController.text = text;
                      _join(text);
                    } else {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('No invite link or code in clipboard.')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('Paste Code or Link from Clipboard'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close Camera'),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLoading = context.watch<SessionProvider>().isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Group Check'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter Join Code',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: isDark ? AppColors.darkText : AppColors.lightText,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter the temporary code provided by your group organizer or scan their QR code.',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
              ),
            ),
            const SizedBox(height: 28),

            Form(
              key: _formKey,
              child: TextFormField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. HN-123456',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white24 : Colors.black26,
                    letterSpacing: 2,
                  ),
                  prefixIcon: const Icon(Icons.tag_rounded),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () => _codeController.clear(),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a join code';
                  }
                  return null;
                },
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isLoading
                    ? null
                    : () {
                        if (_formKey.currentState!.validate()) {
                          _join(_codeController.text);
                        }
                      },
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.login_rounded),
                label: Text(isLoading ? 'Joining...' : 'Join Session'),
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(child: Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR SCAN',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: isDark ? AppColors.darkBorder : AppColors.lightBorder)),
              ],
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _simulateQrScan,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan QR Code with Camera'),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
