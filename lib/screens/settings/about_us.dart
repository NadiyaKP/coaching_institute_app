import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:simple_icons/simple_icons.dart';
import '../../common/theme_color.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'About Us',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.primaryYellow,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 12),
                
                // Logo Image
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.15),
                        spreadRadius: 1,
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/images/signature_logo.png',
                    height: 70,
                    fit: BoxFit.contain,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Tagline
                const Text(
                  'Committed to Academic Excellence\nShaping Skilled Professionals',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                    height: 1.3,
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Description
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryYellow.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primaryYellow.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    'Signature offers a focused approach to commerce and management education, preparing students with both knowledge and practical skills. We develop well-rounded professionals ready to succeed in any business environment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey,
                      height: 1.4,
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Courses Section Header
                const Text(
                  'Courses We Offer',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Course List
                _buildCourseItem(
                  'CA',
                  'Chartered Accountancy',
                  Icons.account_balance,
                ),
                const SizedBox(height: 8),
                
                _buildCourseItem(
                  'CMA IND',
                  'Cost and Management Accounting India',
                  Icons.analytics,
                ),
                const SizedBox(height: 8),
                
                _buildCourseItem(
                  'CS',
                  'Company Secretary India',
                  Icons.gavel,
                ),
                const SizedBox(height: 8),
                
                _buildCourseItem(
                  'CMA US',
                  'Cost and Management Accounting US',
                  Icons.public,
                ),
                const SizedBox(height: 8),
                
                _buildCourseItem(
                  'ACCA',
                  'Association of Chartered Certified Accountants',
                  Icons.language,
                ),
                
                const SizedBox(height: 16),
                
                // Contact Information Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primaryYellow.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Location
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.location_on,
                            color: AppColors.primaryYellow,
                            size: 16,
                          ),
                           SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ayesha Tower, Opp. Reliance Petrol Pump\nCalicut Rd, Valanchery\nKerala, 676552',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textGrey,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // Contact Numbers
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.phone,
                            color: AppColors.primaryYellow,
                            size: 16,
                          ),
                           SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '+91 90745 70207',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textGrey,
                                  ),
                                ),
                                Text(
                                  '+91 85920 00085',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // Social Media Icons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildSocialIcon(
                            SimpleIcons.facebook,
                            'https://www.facebook.com/people/Signature-Institute/61574634887436/',
                            const Color(0xFF1877F2), // Facebook Blue
                          ),
                          const SizedBox(width: 12),
                          _buildSocialIcon(
                            SimpleIcons.instagram,
                            'https://www.instagram.com/signature.institute/',
                            const Color(0xFFE4405F), // Instagram Pink
                          ),
                          const SizedBox(width: 12),
                          _buildSocialIcon(
                            SimpleIcons.linkedin,
                            'https://www.linkedin.com/company/signature-institute/',
                            const Color(0xFF0A66C2), // LinkedIn Blue
                          ),
                          const SizedBox(width: 12),
                          _buildSocialIcon(
                            Icons.language,
                            'https://www.signaturecampus.com/',
                            const Color(0xFF4285F4), // Website Blue
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialIcon(IconData icon, String url, Color iconColor) {
    return GestureDetector(
      onTap: () => _launchUrl(url),
      child: Icon(
        icon,
        color: iconColor,
        size: 24,
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
      } else {
        debugPrint('Could not launch $urlString');
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }

  Widget _buildCourseItem(String title, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryYellow.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.primaryYellow.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryYellow.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: AppColors.primaryYellow,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}