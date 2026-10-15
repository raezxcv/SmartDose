import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

/// Unified, consistent avatar widget across patient and caregiver dashboards,
/// pairing flows, profile screens, and contact lists.
class AppAvatar extends StatelessWidget {
  final String? photoUrl;
  final String? imageUrl;
  final String name;
  final double? size;
  final double? radius;
  final int gradientIndex;
  final bool showBorder;
  final bool? showGradientBorder;
  final Color? borderColor;
  final double borderWidth;

  const AppAvatar({
    super.key,
    this.photoUrl,
    this.imageUrl,
    required this.name,
    this.size,
    this.radius,
    this.gradientIndex = 0,
    this.showBorder = true,
    this.showGradientBorder,
    this.borderColor,
    this.borderWidth = 1.5,
  });

  static const List<List<Color>> avatarGradients = [
    [Color(0xFF00C882), Color(0xFF00A36C)], // Emerald Mint
    [Color(0xFF06B6D4), Color(0xFF0891B2)], // Ocean Cyan
    [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // Royal Purple
    [Color(0xFFEC4899), Color(0xFFDB2777)], // Vibrant Pink
    [Color(0xFFF43F5E), Color(0xFFE11D48)], // Coral Rose
    [Color(0xFF475569), Color(0xFF1E293B)], // Midnight Slate
  ];

  static String getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'SD';
    final parts = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts.first.isNotEmpty) {
      return parts.first.length >= 2
          ? parts.first.substring(0, 2).toUpperCase()
          : parts.first[0].toUpperCase();
    }
    return 'SD';
  }

  @override
  Widget build(BuildContext context) {
    final initials = getInitials(name);
    final actualPhoto = photoUrl ?? imageUrl;
    final effectiveSize = size ?? (radius != null ? radius! * 2 : 44.0);
    final effectiveShowBorder = showGradientBorder ?? showBorder;
    final activeGradIdx = gradientIndex.clamp(0, avatarGradients.length - 1);
    final activeGradient = avatarGradients[activeGradIdx];
    final borderCol = borderColor ?? activeGradient.last;

    return Container(
      width: effectiveSize,
      height: effectiveSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: activeGradient),
        border: effectiveShowBorder ? Border.all(color: borderCol, width: borderWidth) : null,
        boxShadow: [
          BoxShadow(
            color: activeGradient.last.withValues(alpha: 0.25),
            blurRadius: effectiveSize * 0.18,
            offset: Offset(0, effectiveSize * 0.05),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(effectiveSize / 2),
        child: _buildImage(initials, actualPhoto, effectiveSize),
      ),
    );
  }

  Widget _buildImage(String initials, String? photo, double s) {
    final trimmed = (photo ?? '').trim();
    if (trimmed.isEmpty) {
      return _buildInitialsPlaceholder(initials, s);
    }

    if (trimmed.startsWith('data:image')) {
      try {
        final base64Str = trimmed.contains(',') ? trimmed.split(',').last : trimmed;
        final bytes = base64Decode(base64Str);
        return Image.memory(
          bytes,
          width: s,
          height: s,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _buildInitialsPlaceholder(initials, s),
        );
      } catch (_) {
        return _buildInitialsPlaceholder(initials, s);
      }
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Image.network(
        trimmed,
        width: s,
        height: s,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildInitialsPlaceholder(initials, s),
      );
    }

    final file = File(trimmed);
    if (file.existsSync()) {
      return Image.file(
        file,
        width: s,
        height: s,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildInitialsPlaceholder(initials, s),
      );
    }

    return _buildInitialsPlaceholder(initials, s);
  }

  Widget _buildInitialsPlaceholder(String initials, double s) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: s * 0.38,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
