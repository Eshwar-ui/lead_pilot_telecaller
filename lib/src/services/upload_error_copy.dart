import '../core/api/api_exception.dart';

/// Human copy for a recording upload/processing failure, shared by every
/// upload flow (Upload Recording sheet, Add Outbound Lead) so they don't each
/// carry their own slightly-different copy of the same classification.
///
/// Checks [ApiException.isTimeout] before [ApiException.isNetworkError] —
/// both are true for a timeout (neither carries a status code), but a
/// timeout means the request never got an answer back in time, not that the
/// connection is down. The backend's analysis pipeline isn't cancelled when
/// the app stops waiting for it (see `_process_uploaded_recording` in the
/// backend) — it keeps running in its own background thread — so a timeout
/// here means "still working," not "something broke," and telling the user
/// to "check your connection" when their network and the backend are both
/// fine is actively misleading.
String describeUploadError(Object e) {
  if (e is ApiException) {
    if (e.isTimeout) {
      return "Still processing — this call's analysis is taking longer than "
          'usual (long calls and busy hours can take several minutes). It '
          "keeps running in the background even after this screen's timeout; "
          'check back shortly.';
    }
    if (e.isNetworkError) {
      return 'Network error — check your connection and retry.';
    }
    if (e.isUnauthorized) return 'Session expired — please log in again.';
    if (e.isServerError) {
      return 'Server error while processing the recording. Please retry.';
    }
    return e.message;
  }
  return e.toString();
}
