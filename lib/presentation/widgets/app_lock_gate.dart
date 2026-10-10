import 'package:ai_bank_receipt_manager/application/providers/backup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Blocks the desk until PIN or biometric unlock when app lock is enabled.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  var _checking = true;
  var _required = false;
  final _pin = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final lock = ref.read(appLockServiceProvider);
    final enabled = await lock.isEnabled();
    if (!enabled) {
      ref.read(appUnlockedProvider.notifier).setUnlocked(true);
      if (mounted) {
        setState(() {
          _checking = false;
          _required = false;
        });
      }
      return;
    }
    if (await lock.biometricEnabled()) {
      final ok = await lock.unlockWithBiometrics();
      if (ok) {
        ref.read(appUnlockedProvider.notifier).setUnlocked(true);
        if (mounted) {
          setState(() {
            _checking = false;
            _required = false;
          });
        }
        return;
      }
    }
    if (mounted) {
      setState(() {
        _checking = false;
        _required = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = ref.watch(appUnlockedProvider);
    if (_checking) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (!_required || unlocked) {
      return widget.child;
    }
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'AI Bank Receipt Manager is locked',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    final ok = await ref
                        .read(appLockServiceProvider)
                        .verifyPin(_pin.text);
                    if (ok) {
                      ref.read(appUnlockedProvider.notifier).setUnlocked(true);
                      setState(() => _error = null);
                    } else {
                      setState(() => _error = 'Incorrect PIN');
                    }
                  },
                  child: const Text('Unlock'),
                ),
                TextButton(
                  onPressed: () async {
                    final ok = await ref
                        .read(appLockServiceProvider)
                        .unlockWithBiometrics();
                    if (ok) {
                      ref.read(appUnlockedProvider.notifier).setUnlocked(true);
                    }
                  },
                  child: const Text('Use biometrics'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
