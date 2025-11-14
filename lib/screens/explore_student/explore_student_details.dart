import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:coaching_institute_app/service/api_config.dart';
import 'package:coaching_institute_app/common/theme_color.dart';
import '../explore_student/student_document_view.dart';

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

  StudentDetails({
    required this.name,
    required this.gender,
    required this.studentType,
    required this.registerNumber,
    required this.course,
    this.subcourse,
    required this.batch,
    required this.batchType,
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

    HttpClient? httpClient;

    try {
      httpClient = ApiConfig.createHttpClient();

      final request = await httpClient.getUrl(
        Uri.parse('${ApiConfig.baseUrl}/api/students/explore/$studentId/documents/'),
      );

      ApiConfig.commonHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });

      final httpResponse = await request.close().timeout(
        ApiConfig.requestTimeout,
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      final responseBody = await httpResponse.transform(utf8.decoder).join();

      debugPrint('=== FETCH STUDENT DETAILS RESPONSE ===');
      debugPrint('Status: ${httpResponse.statusCode}');
      debugPrint('Body: $responseBody');

      if (httpResponse.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(responseBody);

        if (responseData['success'] == true) {
          _studentDetails = StudentDetails.fromJson(responseData['student']);
          _documents = (responseData['documents'] as List)
              .map((doc) => StudentDocument.fromJson(doc))
              .toList();
        } else {
          throw Exception('Failed to fetch student details');
        }
      } else {
        throw Exception('Server error: ${httpResponse.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching student details: $e');
      _errorMessage = 'Failed to load student details: ${e.toString()}';
    } finally {
      httpClient?.close();
      _isLoading = false;
      notifyListeners();
    }
  }
}

// ============= SKELETON LOADERS =============
class DetailsSkeleton extends StatelessWidget {
  const DetailsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header skeleton
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppGradients.background,
            ),
            child: Column(
              children: [
                const SkeletonLoader(width: 100, height: 100, borderRadius: BorderRadius.all(Radius.circular(50))),
                const SizedBox(height: 16),
                SkeletonLoader(width: 200, height: 24, borderRadius: BorderRadius.circular(4)),
                const SizedBox(height: 8),
                SkeletonLoader(width: 120, height: 16, borderRadius: BorderRadius.circular(4)),
              ],
            ),
          ),
          
          // Details skeleton
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: List.generate(6, (index) => 
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SkeletonLoader(
                    width: double.infinity,
                    height: 80,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
              colors: [
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

  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
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

  Widget _buildHeader() {
    final student = _provider.studentDetails;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppGradients.background,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppGradients.primaryYellow,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowYellow.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person,
                  size: 50,
                  color: AppColors.white,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                student?.name ?? widget.studentName,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryBlue,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: AppColors.primaryBlue.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.badge,
                      size: 16,
                      color: AppColors.primaryBlue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      student?.registerNumber ?? '',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryBlue,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    Color? iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.grey200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowGrey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  (iconColor ?? AppColors.primaryBlue).withOpacity(0.2),
                  (iconColor ?? AppColors.primaryBlue).withOpacity(0.1),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconColor ?? AppColors.primaryBlue,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.grey800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentDetails() {
    final student = _provider.studentDetails;
    if (student == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  gradient: AppGradients.primaryYellow,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Student Information',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildInfoTile(
            icon: Icons.school_outlined,
            label: 'COURSE',
            value: student.course,
            iconColor: const Color(0xFF2196F3),
          ),
          if (student.subcourse != null && student.subcourse!.isNotEmpty)
            _buildInfoTile(
              icon: Icons.subject_outlined,
              label: 'SUBCOURSE',
              value: student.subcourse!,
              iconColor: const Color(0xFF9C27B0),
            ),
          _buildInfoTile(
            icon: Icons.group_outlined,
            label: 'BATCH',
            value: student.batch,
            iconColor: const Color(0xFFFF9800),
          ),
          _buildInfoTile(
            icon: Icons.category_outlined,
            label: 'BATCH TYPE',
            value: student.batchType.toUpperCase(),
            iconColor: const Color(0xFFE91E63),
          ),
          _buildInfoTile(
            icon: student.gender.toLowerCase() == 'male' 
                ? Icons.male 
                : Icons.female,
            label: 'GENDER',
            value: student.gender,
            iconColor: student.gender.toLowerCase() == 'male' 
                ? const Color(0xFF2196F3) 
                : const Color(0xFFE91E63),
          ),
          _buildInfoTile(
            icon: Icons.badge_outlined,
            label: 'STUDENT TYPE',
            value: student.studentType,
            iconColor: const Color(0xFF4CAF50),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(StudentDocument document) {
    return InkWell(
      onTap: () => _handleDocumentTap(document),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
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
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: document.documentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                document.documentIcon,
                color: document.documentColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.grey800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 11,
                        color: AppColors.grey500,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        document.formattedDate,
                        style: const TextStyle(
                          fontSize: 12,
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
              size: 14,
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
      margin: const EdgeInsets.only(bottom: 16),
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
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
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
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type.split('_').map((word) => 
                            word[0].toUpperCase() + word.substring(1).toLowerCase()
                          ).join(' '),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: firstDoc.documentColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${docs.length} document${docs.length > 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: firstDoc.documentColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: firstDoc.documentColor,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: AppColors.grey200),
            Padding(
              padding: const EdgeInsets.all(16),
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
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.description_outlined,
                  size: 48,
                  color: AppColors.grey500,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No documents available',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.grey600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Documents will appear here once uploaded',
                style: TextStyle(
                  fontSize: 14,
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
          Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  gradient: AppGradients.primaryYellow,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Documents',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...sortedTypes.map((type) {
            final docs = groupedDocs[type]!;
            return _buildDocumentSection(type, docs);
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.primaryBlue),
        ),
        title: const Text(
          'Student Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryBlue,
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: ListenableBuilder(
        listenable: _provider,
        builder: (context, child) {
          if (_provider.isLoading) {
            return const DetailsSkeleton();
          }

          if (_provider.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.errorRed.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: AppColors.errorRed,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Failed to load student details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.grey800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _provider.errorMessage!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.grey600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    Container(
                      decoration: BoxDecoration(
                        gradient: AppGradients.primaryYellow,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.shadowYellow.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => _provider.fetchStudentDetails(widget.studentId),
                        icon: const Icon(Icons.refresh, color: AppColors.white),
                        label: const Text(
                          'Retry',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                _buildHeader(),
                _buildStudentDetails(),
                _buildDocumentsSection(),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}