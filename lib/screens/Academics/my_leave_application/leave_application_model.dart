// Model class for Leave Application
class LeaveApplication {
  final String encryptedId;
  final String leaveType;
  final String startDate;
  final String endDate;
  final String reason;
  final String status;
  final String appliedOn;
  final String? markedBy;
  final String? remark;

  LeaveApplication({
    required this.encryptedId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
    required this.appliedOn,
    this.markedBy,
    this.remark,
  });

  factory LeaveApplication.fromJson(Map<String, dynamic> json) {
    return LeaveApplication(
      encryptedId: json['encrypted_id'] ?? '',
      leaveType: json['leave_type'] ?? '',
      startDate: json['start_date'] ?? '',
      endDate: json['end_date'] ?? '',
      reason: json['reason'] ?? '',
      status: json['status'] ?? '',
      appliedOn: json['applied_on'] ?? '',
      markedBy: json['marked_by'],
      remark: json['remark'],
    );
  }
}