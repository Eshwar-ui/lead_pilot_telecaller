/// A telecaller's attendance record for a single day.
///
/// Mirrors the FastAPI attendance payload:
/// `{"id","user_id","telecaller_name","date","check_in_at","check_out_at",
/// "effective_check_out_at","hours_worked","status"}`.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.date,
    this.checkInAt,
    this.checkOutAt,
    this.effectiveCheckOutAt,
    this.hoursWorked,
    this.status = 'on_shift',
  });

  final String id;
  final String date;
  final DateTime? checkInAt;

  /// Raw persisted check-out (null if the telecaller never checked out).
  final DateTime? checkOutAt;

  /// Real check-out, or the 12h auto-cap for a forgotten checkout. Null while
  /// genuinely still on shift.
  final DateTime? effectiveCheckOutAt;
  final double? hoursWorked;

  /// 'completed' | 'on_shift' | 'auto_closed' (forgotten checkout).
  final String status;

  bool get isCheckedIn => checkInAt != null;
  bool get isCheckedOut => checkOutAt != null;
  bool get isCompleted => status == 'completed';
  bool get isOnShift => status == 'on_shift';
  bool get isAutoClosed => status == 'auto_closed';

  /// An empty/unknown-yet record, used before the first fetch resolves.
  factory AttendanceRecord.empty() => const AttendanceRecord(id: '', date: '');

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) {
    DateTime? parseTs(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return AttendanceRecord(
      id: (j['id'] ?? '').toString(),
      date: (j['date'] ?? '').toString(),
      checkInAt: parseTs(j['check_in_at']),
      checkOutAt: parseTs(j['check_out_at']),
      effectiveCheckOutAt: parseTs(j['effective_check_out_at']),
      hoursWorked: j['hours_worked'] is num
          ? (j['hours_worked'] as num).toDouble()
          : null,
      status: (j['status'] ?? 'on_shift').toString(),
    );
  }
}
