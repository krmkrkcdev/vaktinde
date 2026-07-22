import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../state/auth_store.dart';

/// Giriş ve kayıt ekranı.
///
/// Bulut yedekleme isteğe bağlıdır: kullanıcı hesap açmadan da uygulamayı
/// tam olarak kullanabilir. Bu ekran yalnızca ayarlardan açılır.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.startWithRegister = false});

  final bool startWithRegister;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late bool _isRegister = widget.startWithRegister;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);

    final auth = context.read<AuthStore>();
    final navigator = Navigator.of(context);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      if (_isRegister) {
        await auth.register(email, password);
      } else {
        await auth.signIn(email, password);
      }
      navigator.pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } on NetworkUnavailableException {
      setState(() {
        _error = 'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.';
      });
    } catch (e) {
      setState(() => _error = 'Beklenmeyen bir hata oluştu: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = context.watch<AuthStore>().isBusy;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isRegister ? 'Hesap oluştur' : 'Giriş yap'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Icon(Icons.cloud_outlined, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              _isRegister
                  ? 'Kayıtlarınız güvenle yedeklensin'
                  : 'Kayıtlarınıza geri dönün',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Telefonunuzu değiştirdiğinizde giriş yapmanız yeterli; '
              'hatırlatmalarınız ve belge fotoğraflarınız geri gelir.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),

            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                labelText: 'E-posta',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'E-posta adresinizi yazın';
                if (!text.contains('@') || !text.contains('.')) {
                  return 'Geçerli bir e-posta adresi yazın';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),

            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              autofillHints: [
                _isRegister ? AutofillHints.newPassword : AutofillHints.password,
              ],
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                labelText: 'Şifre',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (value) {
                if ((value ?? '').isEmpty) return 'Şifrenizi yazın';
                if (_isRegister && value!.length < 8) {
                  return 'Şifre en az 8 karakter olmalı';
                }
                return null;
              },
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: scheme.onErrorContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(58),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(_isRegister ? 'Hesap oluştur' : 'Giriş yap'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                        _isRegister = !_isRegister;
                        _error = null;
                      }),
              child: Text(
                _isRegister
                    ? 'Zaten hesabım var, giriş yap'
                    : 'Hesabım yok, oluştur',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
