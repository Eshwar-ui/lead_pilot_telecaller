import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Renders the founder-managed organisation logo throughout the signed-in app.
/// Web uploads are stored as data URLs, so base64 PNG/JPG and SVG are handled
/// alongside ordinary remote image URLs.
class OrganizationLogo extends StatelessWidget {
  const OrganizationLogo({
    super.key,
    required this.orgName,
    this.url,
    this.size = 44,
  });

  final String orgName;
  final String? url;
  final double size;

  /// Decode budget for this tile. Images are cached at their DECODED size,
  /// not their display size, so without this the 1095x975 source would sit in
  /// the cache as ~4.3 MB to fill a 44 px square.
  int _decodeWidth(BuildContext context) =>
      (size * MediaQuery.devicePixelRatioOf(context)).round();

  Widget _fallback(BuildContext context) => Image.asset(
    'assets/images/asan_logo.png',
    fit: BoxFit.contain,
    excludeFromSemantics: true,
    cacheWidth: _decodeWidth(context),
  );

  ({String mime, Uint8List bytes})? _decodeDataUrl(String value) {
    final comma = value.indexOf(',');
    if (!value.startsWith('data:image/') || comma < 0) return null;
    try {
      final header = value.substring(5, comma);
      final mime = header.split(';').first.toLowerCase();
      final payload = value.substring(comma + 1);
      final bytes = header.contains(';base64')
          ? base64Decode(payload)
          : Uint8List.fromList(utf8.encode(Uri.decodeComponent(payload)));
      return (mime: mime, bytes: bytes);
    } catch (_) {
      return null;
    }
  }

  Widget _image(BuildContext context, String value) {
    final decodeWidth = _decodeWidth(context);
    final data = _decodeDataUrl(value);
    if (data != null) {
      if (data.mime == 'image/svg+xml') {
        return SvgPicture.memory(
          data.bytes,
          width: size,
          height: size,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => _fallback(context),
        );
      }
      return Image.memory(
        data.bytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        // Founder-uploaded, so its dimensions are whatever they happened to
        // upload — a 2000x2000 PNG would otherwise cost 16 MB of cache to
        // fill this tile.
        cacheWidth: decodeWidth,
        errorBuilder: (_, _, _) => _fallback(context),
      );
    }

    final isSvg =
        Uri.tryParse(value)?.path.toLowerCase().endsWith('.svg') ?? false;
    if (isSvg) {
      return SvgPicture.network(
        value,
        width: size,
        height: size,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        placeholderBuilder: (_) => _fallback(context),
        errorBuilder: (_, _, _) => _fallback(context),
      );
    }
    return Image.network(
      value,
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      cacheWidth: decodeWidth,
      errorBuilder: (_, _, _) => _fallback(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = url?.trim() ?? '';
    return Semantics(
      label: orgName.isEmpty ? 'Organisation logo' : '$orgName logo',
      image: true,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.08),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.westar),
        ),
        clipBehavior: Clip.antiAlias,
        child: value.isEmpty
            ? _fallback(context)
            : _image(context, value),
      ),
    );
  }
}
