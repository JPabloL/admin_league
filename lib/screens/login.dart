import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:admin_league/theme/app_theme.dart';
import 'package:admin_league/models/user_model.dart';
import 'package:admin_league/services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  final ApiService _apiService = ApiService();
  static const String AUTH_COOKIE_KEY = 'lga-mn-sr';

  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _checkIfLoggedIn();
  }

  Future<void> _checkIfLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final String? userJson = prefs.getString(AUTH_COOKIE_KEY);
    if (userJson != null && mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final response = await _apiService.initSession(email, password);

      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic> results = response.data;
        if (results.isNotEmpty) {
          final userRaw = results[0];
          if (email == userRaw['mail'] && password == userRaw['pass']) {
            final userData = UserModel.fromJson(userRaw);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(AUTH_COOKIE_KEY, userData.toRawJson());
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Bienvenido'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppColors.success,
                ),
              );
              Navigator.pushReplacementNamed(context, '/home');
            }
          } else {
            _showError('Credenciales incorrectas.');
          }
        } else {
          _showError('Usuario no encontrado.');
        }
      } else {
        _showError('Error de conexión con el servidor.');
      }
    } catch (e) {
      _showError('Error inesperado. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Colores específicos para esta pantalla (inspirados en el diseño adjunto)
  static const _bgGradientTop = Color(0xFFF3F6FB);
  static const _bgGradientBottom = Color(0xFFFFFFFF);
  static const _pillFieldColor = Color(0xFFF4F6FB);
  static const _darkButton = Color(0xFF111827);
  static const _labelGrey = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgGradientTop, _bgGradientBottom],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildLoginCard(textTheme),
                  const SizedBox(height: AppSpacing.lg),
                  _buildFooter(textTheme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.sports_football_rounded,
              size: 28,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'TOCHITO PRO',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'TOURNAMENT ADMIN',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 2,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard(TextTheme textTheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Welcome Back',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Please sign in to continue',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Email
            _buildFieldLabel('Email Address'),
            const SizedBox(height: 6),
            _buildEmailField(),
            const SizedBox(height: AppSpacing.md),

            // Password
            _buildFieldLabel('Password'),
            const SizedBox(height: 6),
            _buildPasswordField(),

            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Forgot Password?',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _darkButton,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Log In',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: _labelGrey,
      ),
    );
  }

  Widget _buildEmailField() {
    return Container(
      decoration: BoxDecoration(
        color: _pillFieldColor,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildInputIconContainer(
            icon: Icons.mail_outline_rounded,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'admin@tochitopro.com',
              ),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Requerido';
                if (!value.contains('@')) return 'Correo inválido';
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        color: _pillFieldColor,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildInputIconContainer(
            icon: Icons.lock_outline_rounded,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: _passwordController,
              obscureText: _obscureText,
              onFieldSubmitted: (_) => _login(),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '••••••••',
              ),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Requerida';
                return null;
              },
            ),
          ),
          IconButton(
            icon: Icon(
              _obscureText
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
            onPressed: () =>
                setState(() => _obscureText = !_obscureText),
          ),
        ],
      ),
    );
  }

  Widget _buildInputIconContainer({required IconData icon}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Icon(
        icon,
        size: 18,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildFooter(TextTheme textTheme) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.sm),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            children: [
              const TextSpan(text: "Don't have an account? "),
              TextSpan(
                text: 'Contact Support',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Privacy   •   Terms   •   Help',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'v2.0.1  •  TochitoPro Admin Console',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}
