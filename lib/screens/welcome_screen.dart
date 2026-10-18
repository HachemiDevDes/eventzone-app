import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import '../providers/auth_providers.dart';
import 'package:easy_localization/easy_localization.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 10),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseProvider);
      
      // Native in-app Google Sign-In flow (serverClientId requests the ID token for Supabase)
      final googleSignIn = GoogleSignIn(
        serverClientId: '776224860515-7km7k2q9oa0vrfmc7vtk66kbdl1sjmng.apps.googleusercontent.com',
        scopes: const ['email', 'profile'],
      );
      
      // Clear any cached credentials so account selection is clean and reliable
      try {
        await googleSignIn.signOut();
      } catch (_) {}

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return; // User dismissed account selection
      }
      
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;
      
      if (idToken == null) {
        throw 'No Google ID Token returned by Google Play Services';
      }
      
      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } catch (e) {
      debugPrint("Native Google Sign-In error: $e. Attempting web OAuth fallback...");
      try {
        // Seamless fallback to Supabase Web OAuth if native Play Services fails (e.g. Code 10 SHA-1 mismatch)
        final supabase = ref.read(supabaseProvider);
        await supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: 'eventzone://login-callback',
        );
      } catch (fallbackError) {
        debugPrint("Google OAuth fallback error: $fallbackError");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Google sign-in failed. Please try again.".tr()),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final supabase = ref.read(supabaseProvider);
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      
      if (credential.identityToken == null) {
        throw 'No identity token found';
      }
      
      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: credential.identityToken!,
      );
    } catch (e) {
      debugPrint("Apple Sign-In failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Apple sign-in failed. Please try again.".tr()),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EventzoneTheme.backgroundStart,
      body: Stack(
        children: [
          // Background Gradient Animation
          AnimatedBuilder(
            animation: _animController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      0.5 * (1 - _animController.value),
                      -0.5 * (1 - _animController.value),
                    ),
                    radius: 1.5,
                    colors: const [
                      Color(0xFF0F1B35),
                      Color(0xFF0B0F19),
                      Color(0xFF06080F),
                    ],
                  ),
                ),
              );
            },
          ),
          
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top half: Logo & Header
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Eventzone Premium Logo
                          Image.asset(
                            "assets/images/logo.png",
                            height: 32, // Optimal premium size
                            color: Colors.white,
                            colorBlendMode: BlendMode.srcIn,
                            fit: BoxFit.contain,
                          ),
                          SizedBox(height: 12),
                          Text(
                            "Where professionals connect".tr(),
                            style: TextStyle(
                              
                              fontSize: 16,
                              fontWeight: FontWeight.w300,
                              color: Colors.white60,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom half: Onboarding Card
                  GlassContainer(
                    borderRadius: 24,
                    padding: EdgeInsets.all(28.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          "Your professional network starts here".tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Connect with the right people at every event".tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            
                            fontSize: 14,
                            fontWeight: FontWeight.w300,
                            color: Colors.white38,
                          ),
                        ),
                        SizedBox(height: 32),

                        // Google Sign-In Button
                        _isLoading
                            ? Center(
                                child: CircularProgressIndicator(
                                  color: EventzoneTheme.primaryAction,
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: _handleGoogleSignIn,
                                icon: Image.network(
                                  'https://developers.google.com/identity/images/g-logo.png',
                                  height: 20,
                                  width: 20,
                                  errorBuilder: (context, error, stackTrace) => Icon(Icons.g_mobiledata, color: Colors.black, size: 30),
                                ),
                                label: Text(
                                  "Continue with Google".tr(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Color(0xFF0F172A),
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                              ),
                        SizedBox(height: 16),

                        // Apple Sign-In Button
                        if (!_isLoading)
                          ElevatedButton.icon(
                            onPressed: _handleAppleSignIn,
                            icon: Icon(Icons.apple, color: Colors.white, size: 24),
                            label: Text(
                              "Continue with Apple".tr(),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                                side: BorderSide(color: Colors.white24, width: 1),
                              ),
                            ),
                          ),
                        if (!_isLoading) SizedBox(height: 16),

                        // OR Divider
                        Row(
                          children: [
                            const Expanded(child: Divider(color: Colors.white12)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                "or".tr(),
                                style: const TextStyle(
                                  color: Colors.white24,
                                  fontSize: 14,
                                  
                                ),
                              ),
                            ),
                            const Expanded(child: Divider(color: Colors.white12)),
                          ],
                        ),
                        SizedBox(height: 16),

                        // Email Sign-In Button
                        ElevatedButton(
                          onPressed: () => context.push('/signin'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: EventzoneTheme.primaryAction,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: Text(
                            "Sign in with Email".tr(),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        SizedBox(height: 20),

                        // Sign Up Link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Don't have an account? ".tr(),
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 13,
                                
                              ),
                            ),
                            GestureDetector(
                              onTap: () => context.push('/signin'),
                              child: Text(
                                "Sign up".tr(),
                                style: TextStyle(
                                  color: EventzoneTheme.primaryAction,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
