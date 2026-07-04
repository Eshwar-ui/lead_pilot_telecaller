import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';
import '../core/api/api_exception.dart';
import '../models/attendance_record.dart';

/// Talks to the FastAPI attendance endpoints (`voicesummary-main`).
///
/// Every method lets [ApiException] propagate to the caller (e.g. 409 already
/// checked in/out, 404 no check-in yet) so callers can decide how to react
/// instead of this repository silently swallowing errors.
class AttendanceRepository {
  const AttendanceRepository(this._client);

  final ApiClient _client;

  /// `POST /api/attendance/check-in`. Throws [ApiException] (409) if already
  /// checked in today.
  Future<AttendanceRecord> checkIn() async {
    final body = await _client.post(ApiEndpoints.attendanceCheckIn);
    return _fromBody(body);
  }

  /// `POST /api/attendance/check-out`. Throws [ApiException] (404) if there's
  /// no check-in today, or (409) if already checked out.
  Future<AttendanceRecord> checkOut() async {
    final body = await _client.post(ApiEndpoints.attendanceCheckOut);
    return _fromBody(body);
  }

  /// `GET /api/attendance/today` — current user's today record (fields null
  /// if no check-in yet today).
  Future<AttendanceRecord> today() async {
    final body = await _client.get(ApiEndpoints.attendanceToday);
    return _fromBody(body);
  }

  AttendanceRecord _fromBody(Object? body) => AttendanceRecord.fromJson(
        body is Map<String, dynamic> ? body : const {},
      );
}
