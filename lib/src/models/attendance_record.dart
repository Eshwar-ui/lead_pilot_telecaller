/// A telecaller's attendance record for a single day.
///
/// Mirrors the FastAPI attendance payload:
/// `{"id","user_id","telecaller_name","date","check_in_at","check_out_at","hours_worked"}`.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.date,
    this.checkInAt,
    this.checkOutAt,
    this.hoursWorked,
  });

  final String id;
  final String date;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final double? hoursWorked;

  bool get isCheckedIn => checkInAt != null;
  bool get isCheckedOut => checkOutAt != null;

  /// An empty/unknown-yet record, used before the first fetch resolves.
  factory AttendanceRecord.empty() => const AttendanceRecord(id: '', date: '');

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) {
    DateTime? parseTs(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return AttendanceRecord(
      id: (j['id'] ?? '').toString(),
      date: (j['date'] ?? '').toString(),
      checkInAt: parseTs(j['check_in_at']),
      checkOutAt: parseTs(j['check_out_at']),
      hoursWorked: j['hours_worked'] is num
          ? (j['hours_worked'] as num).toDouble()
          : null,
    );
  }
}
