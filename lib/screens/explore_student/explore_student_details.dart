import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';
import '../explore_student/student_document_view.dart';
import '../../../service/http_interceptor.dart';

// ============= MODELS =============
class StudentDetails {
  final String name;
  final String gender;
  final String studentType;
  final String registerNumber;
  final String course;
  final String? subcourse;
  final String batch;
  final String batchType;
  final String? email;

  StudentDetails({
    required this.name,
    required this.gender,
    required this.studentType,
    required this.registerNumber,
    required this.course,
    this.subcourse,
    required this.batch,
    required this.batchType,
    this.email,
  });

  factory StudentDetails.fromJson(Map<String, dynamic> json) {
    return StudentDetails(
      name: json['name'] ?? '',
      gender: json['gender'] ?? '',
      studentType: json['student_type'] ?? '',
      registerNumber: json['register_number'] ?? '',
      course: json['course'] ?? '',
      subcourse: json['subcourse'],
      batch: json['batch'] ?? '',
      batchType: json['batch_type'] ?? '',
      email: json['email'],
    );
  }
}

class StudentDocument {
  final String id;
  final String documentType;
  final String title;
  final String fileUrl;
  final String uploadedAt;

  StudentDocument({
    required this.id,
    required this.documentType,
    required this.title,
    required this.fileUrl,
    required this.uploadedAt,
  });

  factory StudentDocument.fromJson(Map<String, dynamic> json) {
    return StudentDocument(
      id: json['id'] ?? '',
      documentType: json['document_type'] ?? '',
      title: json['title'] ?? '',
      fileUrl: json['file_url'] ?? '',
      uploadedAt: json['uploaded_at'] ?? '',
    );
  }

  String get formattedDate {
    try {
      final dateTime = DateTime.parse(uploadedAt);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  String get fileName {
    return '$title.pdf';
  }

  IconData get documentIcon {
    switch (documentType.toUpperCase()) {
      case 'CERTIFICATE':
        return Icons.workspace_premium;
      case 'ACHIEVEMENT':
        return Icons.emoji_events;
      case 'CV':
        return Icons.description;
      case 'MARKLIST':
        return Icons.grading;
      case 'OTHER':
        return Icons.insert_drive_file;
      default:
        return Icons.description;
    }
  }

  Color get documentColor {
    switch (documentType.toUpperCase()) {
      case 'CERTIFICATE':
        return const Color(0xFF4CAF50);
      case 'ACHIEVEMENT':
        return const Color(0xFFFF9800);
      case 'CV':
        return const Color(0xFF2196F3);
      case 'MARKLIST':
        return const Color(0xFF9C27B0);
      case 'OTHER':
        return const Color(0xFF607D8B);
      default:
        return AppColors.grey600;
    }
  }
}

// ============= PROVIDER CLASS =============
class ExploreStudentDetailsProvider extends ChangeNotifier {
  bool _isLoading = false;
  StudentDetails? _studentDetails;
  List<StudentDocument> _documents = [];
  String? _errorMessage;
  Map<String, bool> _expandedSections = {};

  bool get isLoading => _isLoading;
  StudentDetails? get studentDetails => _studentDetails;
  List<StudentDocument> get documents => _documents;
  String? get errorMessage => _errorMessage;

  // Group documents by type
  Map<String, List<StudentDocument>> get groupedDocuments {
    final Map<String, List<StudentDocument>> grouped = {};
    for (var doc in _documents) {
      if (!grouped.containsKey(doc.documentType)) {
        grouped[doc.documentType] = [];
      }
      grouped[doc.documentType]!.add(doc);
    }
    return grouped;
  }

  bool isSectionExpanded(String type) {
    return _expandedSections[type] ?? false;
  }

  void toggleSection(String type) {
    _expandedSections[type] = !(_expandedSections[type] ?? false);
    notifyListeners();
  }

  Future<void> fetchStudentDetails(String studentId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/students/explore/$studentId/documents/');
      
      final response = await globalHttpClient.get(
        url,
        headers: ApiConfig.commonHeaders,
      ).timeout(
        ApiConfig.requestTimeout,
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      debugPrint('=== FETCH STUDENT DETAILS RESPONSE ===');
      debugPrint('Status: ${response.statusCode}');
      debugPrint('Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);

        if (responseData['success'] == true) {
          _studentDetails = StudentDetails.fromJson(responseData['student']);
          _documents = (responseData['documents'] as List)
              .map((doc) => StudentDocument.fromJson(doc))
              .toList();
        } else {
          throw Exception('Failed to fetch student details');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching student details: $e');
      _errorMessage = 'Failed to load student details: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

// ============= SKELETON LOADERS =============
class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                AppColors.grey200,
                AppColors.grey300,
                AppColors.grey200,
              ],
              stops: [
                _animation.value - 0.3,
                _animation.value,
                _animation.value + 0.3,
              ].map((stop) => stop.clamp(0.0, 1.0)).toList(),
            ),
          ),
        );
      },
    );
  }
}

// ============= SCREEN CLASS =============
class ExploreStudentDetailsScreen extends StatefulWidget {
  final String studentId;
  final String studentName;

  const ExploreStudentDetailsScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<ExploreStudentDetailsScreen> createState() => _ExploreStudentDetailsScreenState();
}

class _ExploreStudentDetailsScreenState extends State<ExploreStudentDetailsScreen> {
  late ExploreStudentDetailsProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = ExploreStudentDetailsProvider();
    _provider.fetchStudentDetails(widget.studentId);
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  void _handleDocumentTap(StudentDocument document) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentDocumentViewScreen(
          fileUrl: document.fileUrl,
          fileName: document.fileName,
        ),
      ),
    );
  }

  // Helper method to check if a field is valid (not null, not empty, not "Not specified")
  bool _isFieldValid(String? value) {
    if (value == null || value.isEmpty) return false;
    final trimmed = value.trim();
    return trimmed.isNotEmpty && 
           trimmed.toLowerCase() != 'not specified' &&
           trimmed.toLowerCase() != 'n/a';
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text(
              'Student Details',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final student = _provider.studentDetails;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Container(
      width: screenWidth - 120,
      margin: const EdgeInsets.symmetric(horizontal: 60),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryYellow.withOpacity(0.15),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Profile Avatar
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primaryYellow,
                  AppColors.primaryYellowDark,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryYellow.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const CircleAvatar(
              radius: 36,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.person_rounded,
                size: 40,
                color: AppColors.primaryYellow,
              ),
            ),
          ),
          
          const SizedBox(height: 14),
          
          // Name
          Text(
            student?.name ?? widget.studentName,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          
          // Register Number Badge
          if (_isFieldValid(student?.registerNumber)) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryBlue.withOpacity(0.2),
                    AppColors.primaryBlue.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: AppColors.primaryBlue.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 6),
                  Text(
                    student!.registerNumber,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlue,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.primaryYellow.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: AppColors.primaryYellow,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppColors.grey200,
      ),
    );
  }

  Widget _buildInfoField({
    required String label,
    required String value,
    required IconData icon,
    Color? iconColor,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isFirst ? 14 : 12, 16, isLast ? 14 : 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: (iconColor ?? AppColors.primaryYellow).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor ?? AppColors.primaryYellow, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey400,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoSection() {
    final student = _provider.studentDetails;
    if (student == null) return const SizedBox.shrink();

    // Build list of valid fields
    List<Widget> fields = [];
    
    if (_isFieldValid(student.gender)) {
      if (fields.isNotEmpty) fields.add(_buildDivider());
      fields.add(_buildInfoField(
        label: 'GENDER',
        value: student.gender,
        icon: student.gender.toLowerCase() == 'male' ? Icons.male : Icons.female,
        iconColor: student.gender.toLowerCase() == 'male' 
            ? const Color(0xFF2196F3) 
            : const Color(0xFFE91E63),
        isFirst: fields.isEmpty,
      ));
    }
    
    if (_isFieldValid(student.email)) {
      if (fields.isNotEmpty) fields.add(_buildDivider());
      fields.add(_buildInfoField(
        label: 'EMAIL',
        value: student.email!,
        icon: Icons.email_outlined,
        iconColor: const Color(0xFF2196F3),
        isFirst: fields.isEmpty,
      ));
    }
    
    if (_isFieldValid(student.studentType)) {
      if (fields.isNotEmpty) fields.add(_buildDivider());
      fields.add(_buildInfoField(
        label: 'STUDENT TYPE',
        value: student.studentType,
        icon: Icons.badge_outlined,
        iconColor: const Color(0xFF4CAF50),
        isFirst: fields.isEmpty,
      ));
    }

    // If no valid fields, don't show the section
    if (fields.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(children: fields),
      ),
    );
  }

  Widget _buildAcademicInfoSection() {
    final student = _provider.studentDetails;
    if (student == null) return const SizedBox.shrink();

    // Build list of valid fields
    List<Widget> fields = [];
    
    if (_isFieldValid(student.course)) {
      if (fields.isNotEmpty) fields.add(_buildDivider());
      fields.add(_buildInfoField(
        label: 'COURSE',
        value: student.course,
        icon: Icons.menu_book_rounded,
        iconColor: const Color(0xFF2196F3),
        isFirst: fields.isEmpty,
      ));
    }
    
    if (_isFieldValid(student.subcourse)) {
      if (fields.isNotEmpty) fields.add(_buildDivider());
      fields.add(_buildInfoField(
        label: 'LEVEL',
        value: student.subcourse!,
        icon: Icons.book_outlined,
        iconColor: const Color(0xFF9C27B0),
        isFirst: fields.isEmpty,
      ));
    }
    
    if (_isFieldValid(student.batch)) {
      if (fields.isNotEmpty) fields.add(_buildDivider());
      fields.add(_buildInfoField(
        label: 'BATCH',
        value: student.batch,
        icon: Icons.group_outlined,
        iconColor: const Color(0xFFFF9800),
        isFirst: fields.isEmpty,
      ));
    }
    
    if (_isFieldValid(student.batchType)) {
      if (fields.isNotEmpty) fields.add(_buildDivider());
      fields.add(_buildInfoField(
        label: 'BATCH TYPE',
        value: student.batchType.toUpperCase(),
        icon: Icons.category_outlined,
        iconColor: const Color(0xFFE91E63),
        isFirst: fields.isEmpty,
      ));
    }

    // If no valid fields, don't show the section
    if (fields.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(children: fields),
      ),
    );
  }

  Widget _buildDocumentCard(StudentDocument document) {
    return InkWell(
      onTap: () => _handleDocumentTap(document),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: document.documentColor.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: document.documentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                document.documentIcon,
                color: document.documentColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.grey800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 10,
                        color: AppColors.grey500,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        document.formattedDate,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.grey500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios,
              size: 12,
              color: document.documentColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentSection(String type, List<StudentDocument> docs) {
    final isExpanded = _provider.isSectionExpanded(type);
    final firstDoc = docs.first;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: firstDoc.documentColor.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: firstDoc.documentColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => _provider.toggleSection(type),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          firstDoc.documentColor.withOpacity(0.2),
                          firstDoc.documentColor.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      firstDoc.documentIcon,
                      color: firstDoc.documentColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type.split('_').map((word) => 
                            word[0].toUpperCase() + word.substring(1).toLowerCase()
                          ).join(' '),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: firstDoc.documentColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${docs.length} document${docs.length > 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: firstDoc.documentColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: firstDoc.documentColor,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: AppColors.grey200),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: docs.map((doc) => _buildDocumentCard(doc)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDocumentsSection() {
    if (_provider.documents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(36),
        child: Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: const BoxDecoration(
                  color: AppColors.grey200,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.description_outlined,
                  size: 42,
                  color: AppColors.grey500,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No documents available',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Documents will appear here once uploaded',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.grey500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final groupedDocs = _provider.groupedDocuments;
    final sortedTypes = groupedDocs.keys.toList()..sort();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...sortedTypes.map((type) {
            final docs = groupedDocs[type]!;
            return _buildDocumentSection(type, docs);
          }),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // Profile Card Skeleton
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: const BoxDecoration(
                    color: AppColors.grey200,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: 160,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: 110,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 90,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),
          
          // Section Header Skeleton
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 140,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          
          // Info Cards Skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: List.generate(
                  2,
                  (index) => Column(
                    children: [
                      if (index > 0) _buildDivider(),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          index == 0 ? 14 : 12,
                          16,
                          index == 1 ? 14 : 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.grey200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 70,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: AppColors.grey200,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    width: double.infinity,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: AppColors.grey200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
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
              ),
            ),
          ),

          const SizedBox(height: 22),
          
          // Another Section Skeleton
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 160,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: List.generate(
                  4,
                  (index) => Column(
                    children: [
                      if (index > 0) _buildDivider(),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          index == 0 ? 14 : 12,
                          16,
                          index == 3 ? 14 : 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.grey200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 90,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: AppColors.grey200,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Container(
                                    width: double.infinity,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: AppColors.grey200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
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
              ),
            ),
          ),
          
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.errorRed.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: AppColors.errorRed,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Oops! Something went wrong',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _provider.errorMessage ?? 'Unable to load student details',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textGrey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _provider.fetchStudentDetails(widget.studentId),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'Try Again',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryYellow,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Stack(
        children: [
          // Gradient Background
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 200,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primaryYellow,
                    AppColors.primaryYellowDark,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                const SizedBox(height: 8),
                Expanded(
                  child: ListenableBuilder(
                    listenable: _provider,
                    builder: (context, child) {
                      if (_provider.isLoading) {
                        return _buildSkeletonLoading();
                      }

                      if (_provider.errorMessage != null) {
                        return _buildErrorState();
                      }

                      final student = _provider.studentDetails;
                      final hasPersonalInfo = student != null && 
                          (_isFieldValid(student.gender) || _isFieldValid(student.email) || _isFieldValid(student.studentType));
                      final hasAcademicInfo = student != null && 
                          (_isFieldValid(student.course) || _isFieldValid(student.subcourse) || 
                           _isFieldValid(student.batch) || _isFieldValid(student.batchType));

                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            _buildProfileCard(),
                            
                            // Only show Personal Information section if there are valid fields
                            if (hasPersonalInfo) ...[
                              const SizedBox(height: 22),
                              _buildSectionHeader('Personal Information', Icons.person_outline_rounded),
                              _buildPersonalInfoSection(),
                            ],

                            // Only show Academic Information section if there are valid fields
                            if (hasAcademicInfo) ...[
                              const SizedBox(height: 22),
                              _buildSectionHeader('Academic Information', Icons.menu_book_rounded),
                              _buildAcademicInfoSection(),
                            ],

                            // Documents Section - always show header
                            const SizedBox(height: 22),
                            _buildSectionHeader('Documents', Icons.description_outlined),
                            _buildDocumentsSection(),
                            
                            const SizedBox(height: 28),
                          ],
                        ),
                      );
                    },
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