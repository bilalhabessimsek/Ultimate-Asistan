import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final supabase = Supabase.instance.client;
  bool _isLoading = false;
  bool _isSignUp = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        throw 'E-posta ve şifre boş bırakılamaz.';
      }

      if (_isSignUp) {
        final res =
            await supabase.auth.signUp(email: email, password: password);
        if (res.session == null && mounted) {
          setState(() {
            _errorMessage =
                'Kayıt alındı. E-postanı doğruladıktan sonra giriş yapabilirsin.';
          });
        }
      } else {
        await supabase.auth
            .signInWithPassword(email: email, password: password);
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _errorMessage = _friendlyError(err);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Supabase/ham hata metinlerini kullanıcı dostu Türkçe mesaja çevirir.
  String _friendlyError(Object err) {
    final raw = err.toString();

    if (err is AuthException) {
      final msg = err.message.toLowerCase();
      if (msg.contains('invalid login credentials')) {
        return 'E-posta veya şifre hatalı.';
      }
      if (msg.contains('email not confirmed')) {
        return 'E-posta adresin henüz doğrulanmamış.';
      }
      if (msg.contains('already registered') ||
          msg.contains('already exists')) {
        return 'Bu e-posta ile zaten bir hesap var.';
      }
      if (msg.contains('at least 6 characters') ||
          msg.contains('password should be')) {
        return 'Şifre en az 6 karakter olmalı.';
      }
      if (msg.contains('rate limit')) {
        return 'Çok fazla deneme yaptın. Biraz bekleyip tekrar dene.';
      }
      if (msg.contains('unable to validate email') ||
          msg.contains('invalid email')) {
        return 'Geçerli bir e-posta adresi gir.';
      }
      return err.message;
    }

    if (raw.contains('SocketException') ||
        raw.contains('Failed host lookup') ||
        raw.contains('Connection refused') ||
        raw.contains('Connection closed')) {
      return 'Sunucuya bağlanılamadı. İnternetini kontrol et.';
    }

    // Ham metin yerine anlaşılır bir varsayılan.
    return 'İşlem tamamlanamadı. Lütfen tekrar dene.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Başlık / Logo
                const Text(
                  'ULTIMATE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cep Asistanı Giriş Paneli',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 40),

                // Kart Container
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7F1D1D),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // E-posta
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          labelText: 'E-posta',
                          labelStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF0D1117),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Şifre
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Şifre',
                          labelStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF0D1117),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Giriş / Kayıt Butonu
                      ElevatedButton(
                        onPressed: _isLoading ? null : _authenticate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _isLoading
                              ? 'Lütfen bekleyin...'
                              : (_isSignUp ? 'Kayıt Ol' : 'Giriş Yap'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Mod Değiştirme
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isSignUp ? 'Zaten hesabın var mı?' : 'Hesabın yok mu?',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isSignUp = !_isSignUp;
                          _errorMessage = null;
                        });
                      },
                      child: Text(
                        _isSignUp ? 'Giriş Yap' : 'Kayıt Ol',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
