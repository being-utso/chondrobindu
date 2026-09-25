import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_config.dart';
import '../core/constants/app_constants.dart';
import '../providers/user_profile_provider.dart';

/// Help & Support Screen with Material 3 Dark Contact Form.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _contactDetailController;
  final _messageController = TextEditingController();

  String _contactMethod = 'Mail';
  String _reason = 'Syllabus Query';
  bool _isSubmitting = false;

  TextEditingController get _emailController => _contactDetailController;
  String get _selectedContactMethod => _contactMethod;
  String get _selectedReason => _reason;

  final List<String> _contactMethods = [
    'Mail',
    'Phone',
    'WhatsApp',
    'LinkedIn',
    'Instagram',
    'Facebook',
  ];

  final List<String> _reasons = [
    'Syllabus Query',
    'Technical Issue',
    'Feature Request',
    'General Feedback',
    'Other'
  ];

  late final TapGestureRecognizer _devRecognizer;

  @override
  void initState() {
    super.initState();
    _devRecognizer = TapGestureRecognizer()
      ..onTap = () async {
        final Uri url = Uri.parse('https://being-utso.github.io/');
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          await launchUrl(url, mode: LaunchMode.platformDefault);
        }
      };

    final profile = ref.read(userProfileProvider);
    _nameController = TextEditingController(text: profile.fullName);
    _contactDetailController = TextEditingController(
      text: profile.email,
    );
  }

  @override
  void dispose() {
    _devRecognizer.dispose();
    _nameController.dispose();
    _contactDetailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _getDefaultValueForMethod(String method) {
    final profile = ref.read(userProfileProvider);
    switch (method) {
      case 'Mail':
        return profile.email;
      case 'Phone':
      case 'WhatsApp':
        return profile.phone;
      case 'LinkedIn':
        return 'https://linkedin.com/in/${profile.username}';
      case 'Instagram':
        return 'https://instagram.com/${profile.username}';
      case 'Facebook':
        return 'https://facebook.com/${profile.username}';
      default:
        return profile.email;
    }
  }

  String _getDynamicLabel(String method) {
    switch (method) {
      case 'Mail':
        return 'Email Address';
      case 'Phone':
      case 'WhatsApp':
        return 'Phone Number';
      case 'LinkedIn':
      case 'Instagram':
      case 'Facebook':
      default:
        return 'Profile Link';
    }
  }

  TextInputType _getDynamicKeyboardType(String method) {
    switch (method) {
      case 'Mail':
        return TextInputType.emailAddress;
      case 'Phone':
      case 'WhatsApp':
        return TextInputType.phone;
      case 'LinkedIn':
      case 'Instagram':
      case 'Facebook':
      default:
        return TextInputType.url;
    }
  }

  IconData _getDynamicIcon(String method) {
    switch (method) {
      case 'Mail':
        return Icons.email_outlined;
      case 'Phone':
        return Icons.phone_outlined;
      case 'WhatsApp':
        return Icons.chat_bubble_outline_rounded;
      case 'LinkedIn':
        return Icons.work_outline_rounded;
      case 'Instagram':
        return Icons.camera_alt_outlined;
      case 'Facebook':
        return Icons.public_rounded;
      default:
        return Icons.link_rounded;
    }
  }

  String _getDynamicHint(String method) {
    switch (method) {
      case 'Mail':
        return 'Enter your email address';
      case 'Phone':
      case 'WhatsApp':
        return 'Enter your phone number';
      case 'LinkedIn':
        return 'Enter your LinkedIn profile link';
      case 'Instagram':
        return 'Enter your Instagram profile link';
      case 'Facebook':
        return 'Enter your Facebook profile link';
      default:
        return 'Enter details';
    }
  }

  Future<void> _launchUrl(String urlString) async {
    try {
      final Uri url = Uri.parse(urlString);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (!await launchUrl(url, mode: LaunchMode.platformDefault)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFFEF4444),
                behavior: SnackBarBehavior.floating,
                content: Text('Could not open link: $urlString'),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            content: Text('Error launching link: $e'),
          ),
        );
      }
    }
  }

  Future<void> _handleSendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe your query before sending.'),
          backgroundColor: Color(0xFFFF5964),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final response = await http.post(
        Uri.parse(AppConfig.supportContactUrl),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'preferred_contact': _selectedContactMethod,
          'reason': _selectedReason,
          'message': message,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _messageController.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Message sent successfully! We will get back to you soon.',
                style: GoogleFonts.plusJakartaSans(color: Colors.white),
              ),
              backgroundColor: const Color(0xFF06D6A0),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to send message. Please check your connection.',
              style: GoogleFonts.plusJakartaSans(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFFF5964),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _sendMessage() {
    if (_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFF2B78A),
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Message sent successfully via $_contactMethod! We will contact you soon.',
            style: const TextStyle(color: Color(0xFF140F0E), fontWeight: FontWeight.bold),
          ),
        ),
      );
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);

    final dynamicLabel = _getDynamicLabel(_contactMethod);
    final dynamicKeyboard = _getDynamicKeyboardType(_contactMethod);
    final dynamicIcon = _getDynamicIcon(_contactMethod);
    final dynamicHint = _getDynamicHint(_contactMethod);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Help & Support',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.support_agent_rounded, color: accentColor, size: 24),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Contact Support',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'We usually reply within 24 hours',
                      style: TextStyle(
                        color: Colors.blueGrey.shade400,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Form Card
            Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Full Name Field
                    Text(
                      'Full Name',
                      style: TextStyle(
                        color: Colors.blueGrey.shade300,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF170F0D),
                        hintText: 'Enter your name',
                        hintStyle: TextStyle(color: Colors.blueGrey.shade500),
                        prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFFABA093), size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: accentColor),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Preferred Contact Method Dropdown
                    Text(
                      'Preferred Contact Method',
                      style: TextStyle(
                        color: Colors.blueGrey.shade300,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _contactMethod,
                      dropdownColor: cardColor,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF170F0D),
                        prefixIcon: const Icon(Icons.contact_phone_outlined, color: Color(0xFFABA093), size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: accentColor),
                        ),
                      ),
                      items: _contactMethods.map((method) {
                        return DropdownMenuItem<String>(
                          value: method,
                          child: Text(method),
                        );
                      }).toList(),
                      onChanged: (newVal) {
                        if (newVal != null && newVal != _contactMethod) {
                          setState(() {
                            _contactMethod = newVal;
                            _contactDetailController.text = _getDefaultValueForMethod(newVal);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Dynamic Input Field
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          dynamicLabel,
                          style: TextStyle(
                            color: Colors.blueGrey.shade300,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Auto-filled',
                          style: TextStyle(
                            color: accentColor.withOpacity(0.8),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: ValueKey('input_field_$_contactMethod'),
                      controller: _contactDetailController,
                      keyboardType: dynamicKeyboard,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF170F0D),
                        hintText: dynamicHint,
                        hintStyle: TextStyle(color: Colors.blueGrey.shade500),
                        prefixIcon: Icon(dynamicIcon, color: const Color(0xFFABA093), size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: accentColor),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your $dynamicLabel';
                        }
                        if (_contactMethod == 'Mail' && !value.contains('@')) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Reason Dropdown
                    Text(
                      'Reason for Reaching Out',
                      style: TextStyle(
                        color: Colors.blueGrey.shade300,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _reason,
                      dropdownColor: cardColor,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF170F0D),
                        prefixIcon: const Icon(Icons.help_outline_rounded, color: Color(0xFFABA093), size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: accentColor),
                        ),
                      ),
                      items: _reasons.map((reason) {
                        return DropdownMenuItem<String>(
                          value: reason,
                          child: Text(reason),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _reason = val);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Message Field
                    Text(
                      'Your Message',
                      style: TextStyle(
                        color: Colors.blueGrey.shade300,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _messageController,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF170F0D),
                        hintText: 'Describe your query or suggestion in detail...',
                        hintStyle: TextStyle(color: Colors.blueGrey.shade500),
                        contentPadding: const EdgeInsets.all(16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: accentColor),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your message';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Send Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _handleSendMessage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: const Color(0xFF140F0E),
                          disabledBackgroundColor: accentColor.withOpacity(0.5),
                          disabledForegroundColor: const Color(0xFF140F0E).withOpacity(0.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF140F0E)),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.send_rounded, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Send Message',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Quick AI Tutors Section
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFA78BFA).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFA78BFA), size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick AI Tutors',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Instant problem solving & concept explanation',
                      style: TextStyle(
                        color: Colors.blueGrey.shade400,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // AI Tutors Cards Grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: [
                _buildAITutorCard(
                  name: 'Gemini AI',
                  subtitle: 'Google Workspace',
                  icon: Icons.auto_awesome,
                  color: const Color(0xFFF2B78A),
                  url: 'https://gemini.google.com',
                ),
                _buildAITutorCard(
                  name: 'ChatGPT',
                  subtitle: 'OpenAI GPT-4o',
                  icon: Icons.chat_bubble_outline_rounded,
                  color: const Color(0xFF34D399),
                  url: 'https://chatgpt.com',
                ),
                _buildAITutorCard(
                  name: 'Claude AI',
                  subtitle: 'Anthropic Sonnet',
                  icon: Icons.psychology_outlined,
                  color: const Color(0xFFF97316),
                  url: 'https://claude.ai',
                ),
                _buildAITutorCard(
                  name: 'Perplexity',
                  subtitle: 'Realtime Research',
                  icon: Icons.search_rounded,
                  color: const Color(0xFFA78BFA),
                  url: 'https://perplexity.ai',
                ),
              ],
            ),
            const SizedBox(height: 28),

            // About the Developer Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF241C1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF2B78A).withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2B78A).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.code_rounded, color: Color(0xFFF2B78A), size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'About the Developer',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFFABA093),
                              fontSize: 12,
                              height: 1.4,
                            ),
                            children: [
                              const TextSpan(text: 'Crafted by '),
                              TextSpan(
                                text: 'Shahriyer Sayem',
                                style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFFF2B78A),
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                  decorationColor: const Color(0xFFF2B78A).withOpacity(0.6),
                                ),
                                recognizer: _devRecognizer,
                              ),
                              const TextSpan(
                                text:
                                    ' — a distraction-free academic workspace built for university engineering undergraduates, college, and admission students.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Task 2: Support the Project / Donate Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF241C1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.25)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withOpacity(0.04),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.favorite_rounded, color: Color(0xFFF59E0B), size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Support the Project / Donate',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Chondrobindu is 100% free & ad-free for students. You can support continuous maintenance, new features, and server costs:',
                    style: TextStyle(
                      color: Colors.blueGrey.shade300,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Donation Action Buttons Row
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      // Buy Me A Coffee Button
                      ElevatedButton.icon(
                        onPressed: () => _launchUrl('https://being-utso.github.io/contact.html'),
                        icon: const Icon(Icons.coffee_rounded, size: 16, color: Colors.black87),
                        label: const Text(
                          'Buy Me a Coffee',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFDD00),
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),

                      // GitHub Profile Link
                      OutlinedButton.icon(
                        onPressed: () => _launchUrl('https://github.com/being-utso'),
                        icon: const Icon(Icons.code_rounded, size: 16, color: Color(0xFFF2B78A)),
                        label: const Text(
                          'GitHub',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: const Color(0xFFF2B78A).withOpacity(0.4)),
                          backgroundColor: const Color(0xFFF2B78A).withOpacity(0.08),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),

                      // Privacy Policy Link
                      OutlinedButton.icon(
                        onPressed: () => _launchUrl(AppConstants.privacyPolicyUrl),
                        icon: const Icon(Icons.policy_rounded, size: 16, color: Colors.blueGrey),
                        label: const Text(
                          'Privacy Policy',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.blueGrey.withOpacity(0.4)),
                          backgroundColor: Colors.blueGrey.withOpacity(0.08),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _showBkashNagadDialog(BuildContext context) {
    const bkashNumber = AppConstants.donationBkashNumber;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF241C1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.volunteer_activism_rounded, color: Color(0xFFEC4899), size: 22),
            SizedBox(width: 10),
            Text(
              'Donate via bKash',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You can send your support directly via Send Money (Personal):',
              style: TextStyle(color: Colors.blueGrey, fontSize: 12.5),
            ),
            const SizedBox(height: 14),

            // bKash Box
            _buildDonationNumberTile(
              label: 'bKash Personal',
              number: bkashNumber,
              color: const Color(0xFFD82A74),
              ctx: ctx,
            ),

            
            const SizedBox(height: 12),
            Text(
              'Thank you so much for supporting Chondrobindu for Bangladeshi candidates! ❤️',
              style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF140F0E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDonationNumberTile({
    required String label,
    required String number,
    required Color color,
    required BuildContext ctx,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF170F0D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                number,
                style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Color(0xFFF2B78A), size: 18),
            tooltip: 'Copy Number',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: number));
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF10B981),
                  behavior: SnackBarBehavior.floating,
                  content: Text('Copied $label number to clipboard!'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAITutorCard({
    required String name,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String url,
  }) {
    return Material(
      color: const Color(0xFF241C1A),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _launchUrl(url),
        splashColor: color.withOpacity(0.15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.blueGrey.shade400,
                        fontSize: 10.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, color: Colors.blueGrey.shade500, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}
