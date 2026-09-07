import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';
import '../core/api/api_exception.dart';

/// The telecaller's organization, as set up by the founder on the web app —
/// shown on the mobile Profile screen so a telecaller sees who they work for.
class OrgProfile {
  const OrgProfile({
    required this.name,
    this.industry,
    this.websiteUrl,
    this.logoUrl,
    this.address,
  });

  final String name;
  final String? industry;
  final String? websiteUrl;
  final String? logoUrl;
  final String? address;

  factory OrgProfile.fromJson(Map<String, dynamic> j) => OrgProfile(
        name: (j['name'] ?? '').toString(),
        industry: (j['industry'] as String?)?.trim().isEmpty ?? true
            ? null
            : j['industry'] as String?,
        websiteUrl: (j['website_url'] as String?)?.trim().isEmpty ?? true
            ? null
            : j['website_url'] as String?,
        logoUrl: (j['logo_url'] as String?)?.trim().isEmpty ?? true
            ? null
            : j['logo_url'] as String?,
        address: (j['address'] as String?)?.trim().isEmpty ?? true
            ? null
            : j['address'] as String?,
      );
}

/// Talks to the FastAPI org-profile endpoint (`voicesummary-main`).
class OrgProfileRepository {
  const OrgProfileRepository(this._client);

  final ApiClient _client;

  /// `GET /api/auth/org` — any authenticated role (including telecaller) may
  /// call this; it's the same org record the founder edits from the web app.
  Future<OrgProfile> fetch() async {
    final body = await _client.get(ApiEndpoints.orgProfile);
    if (body is! Map<String, dynamic>) {
      throw ApiException('Unexpected org-profile payload');
    }
    return OrgProfile.fromJson(body);
  }

  /// `GET /api/auth/me` — the authoritative user record, as opposed to the
  /// copy embedded in the session at login. Returned raw because
  /// [SessionController.refreshIdentity] persists it in the same shape it
  /// already stores.
  Future<Map<String, dynamic>> me() async {
    final body = await _client.get(ApiEndpoints.me);
    if (body is! Map<String, dynamic>) {
      throw ApiException('Unexpected /api/auth/me payload');
    }
    return body;
  }
}
