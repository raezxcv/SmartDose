import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A widget that connects to a live MJPEG stream URL and renders frames
/// in real-time, giving a true CCTV-like live video experience.
///
/// ## How the MJPEG decoder works
/// The Raspberry Pi server sends a continuous HTTP response with
/// `Content-Type: multipart/x-mixed-replace`. Each JPEG frame is delimited
/// by a `--frame` boundary. This decoder:
///   1. Opens a persistent HTTP GET connection.
///   2. Buffers incoming bytes.
///   3. Detects JPEG Start-of-Image (FF D8) and End-of-Image (FF D9) markers.
///   4. Extracts complete JPEG frames and renders them via [Image.memory]
///      with [gaplessPlayback: true] to avoid flicker between frames.
///   5. Auto-reconnects after errors with a 3-second backoff.
///   6. Re-initialises when [streamUrl] changes (e.g. Pi reboot → new tunnel URL).
///
/// ## Parameters
/// - [streamUrl] — The MJPEG stream URL (e.g. `https://xxxx.trycloudflare.com/stream`)
/// - [isOnline]  — Whether the device is reported online in Firestore
/// - [fit]       — How to inscribe the image into the available space
/// - [showLiveBadge] — Whether to overlay the pulsing ● LIVE badge (default true)
class MjpegStreamView extends StatefulWidget {
  final String? streamUrl;
  final bool isOnline;
  final BoxFit fit;
  final bool showLiveBadge;
  final VoidCallback? onRetry;

  const MjpegStreamView({
    super.key,
    required this.streamUrl,
    required this.isOnline,
    this.fit = BoxFit.cover,
    this.showLiveBadge = true,
    this.onRetry,
  });

  @override
  State<MjpegStreamView> createState() => _MjpegStreamViewState();
}

class _MjpegStreamViewState extends State<MjpegStreamView>
    with SingleTickerProviderStateMixin {

  // ── Decoder state ────────────────────────────────────────────────────────
  http.Client?                  _client;
  StreamSubscription<List<int>>? _sub;
  final List<int>               _buf = [];
  Uint8List?                    _frame;
  _StreamState                  _state = _StreamState.idle;

  /// Maximum raw buffer size (prevents memory blow-up on slow consumers).
  static const int _kMaxBuf = 4 * 1024 * 1024; // 4 MB

  /// JPEG Start-of-Image marker bytes.
  static const List<int> _kSOI = [0xFF, 0xD8];

  /// JPEG End-of-Image marker bytes.
  static const List<int> _kEOI = [0xFF, 0xD9];

  // ── Live-badge pulse animation ───────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _startStream();
  }

  @override
  void didUpdateWidget(MjpegStreamView old) {
    super.didUpdateWidget(old);
    // Reconnect whenever the URL or online-status changes
    if (old.streamUrl != widget.streamUrl ||
        old.isOnline != widget.isOnline) {
      _stopStream();
      _startStream();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _stopStream();
    super.dispose();
  }

  // ── Connection lifecycle ─────────────────────────────────────────────────

  void _startStream() {
    final url = widget.streamUrl;
    if (url == null || url.isEmpty || !widget.isOnline) {
      _setState(_StreamState.idle);
      return;
    }
    _connect(url);
  }

  void _stopStream() {
    _sub?.cancel();
    _client?.close();
    _client = null;
    _sub    = null;
    _buf.clear();
  }

  Future<void> _connect(String url) async {
    if (!mounted) return;
    _setState(_StreamState.connecting);

    try {
      _client = http.Client();
      final request = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent']     = 'Mozilla/5.0 (SmartDoseApp/1.0)'
        ..headers['Connection']     = 'keep-alive'
        ..headers['Cache-Control']  = 'no-cache'
        ..headers['Pragma']         = 'no-cache';

      final response = await _client!
          .send(request)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode != 200) {
        _onError();
        return;
      }

      _sub = response.stream.listen(
        _onData,
        onError: (_) => _onError(),
        onDone:  _onError,
        cancelOnError: false,
      );
    } catch (_) {
      _onError();
    }
  }

  // ── Data processing ──────────────────────────────────────────────────────

  void _onData(List<int> chunk) {
    _buf.addAll(chunk);

    // Keep buffer bounded — if it grows too large, jump to the latest SOI
    if (_buf.length > _kMaxBuf) {
      final last = _rfind(_buf, _kSOI);
      if (last > 0) {
        _buf.removeRange(0, last);
      } else {
        _buf.clear();
        return;
      }
    }

    _extractFrames();
  }

  /// Scans the buffer for complete JPEG frames (SOI → EOI) and emits them.
  void _extractFrames() {
    while (true) {
      // Find next JPEG start
      final si = _find(_buf, _kSOI, 0);
      if (si < 0) {
        // No start marker — keep the last byte (might be 0xFF, first byte of next SOI)
        if (_buf.length > 1) _buf.removeRange(0, _buf.length - 1);
        return;
      }

      // Find JPEG end after the start
      final ei = _find(_buf, _kEOI, si + 2);
      if (ei < 0) {
        // EOI not yet received — trim bytes before SOI and wait for more data
        if (si > 0) _buf.removeRange(0, si);
        return;
      }

      // Extract the complete JPEG
      final frameEnd = ei + 2;
      final frame    = Uint8List.fromList(_buf.sublist(si, frameEnd));
      _buf.removeRange(0, frameEnd);

      if (mounted) {
        setState(() {
          _frame = frame;
          _state = _StreamState.streaming;
        });
      }
    }
  }

  void _onError() {
    if (!mounted) return;
    _stopStream();
    _setState(_StreamState.error);
    // Retry after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _startStream();
    });
  }

  void _setState(_StreamState s) {
    if (mounted) setState(() => _state = s);
  }

  // ── Buffer search helpers ────────────────────────────────────────────────

  /// Returns the index of [seq] in [data] starting from [from], or -1.
  static int _find(List<int> data, List<int> seq, int from) {
    outer:
    for (int i = from; i <= data.length - seq.length; i++) {
      for (int j = 0; j < seq.length; j++) {
        if (data[i + j] != seq[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  /// Returns the last index of [seq] in [data], or -1.
  static int _rfind(List<int> data, List<int> seq) {
    outer:
    for (int i = data.length - seq.length; i >= 0; i--) {
      for (int j = 0; j < seq.length; j++) {
        if (data[i + j] != seq[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final isStreaming  = _state == _StreamState.streaming && _frame != null;
    final isOffline    = !widget.isOnline || widget.streamUrl == null;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Main content area ──────────────────────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: _buildContent(isDark, isOffline, isStreaming),
        ),

        // ── Pulsing ● LIVE badge (always on top when streaming) ───────────
        if (widget.showLiveBadge && isStreaming)
          Positioned(
            top: 14,
            left: 14,
            child: FadeTransition(
              opacity: _pulseAnim,
              child: const _LiveBadge(),
            ),
          ),
      ],
    );
  }

  Widget _buildContent(bool isDark, bool isOffline, bool isStreaming) {
    if (isOffline) {
      return _Placeholder(
        key: const ValueKey('offline'),
        isOnline: false,
        isDark: isDark,
        onRetry: widget.onRetry ?? _startStream,
      );
    }

    return switch (_state) {
      _StreamState.streaming when _frame != null => Image.memory(
        _frame!,
        key: const ValueKey('frame'),
        fit: widget.fit,
        gaplessPlayback: true,
      ),
      _StreamState.connecting => _ConnectingView(
        key: const ValueKey('connecting'),
        isDark: isDark,
      ),
      _StreamState.error => _ErrorView(
        key: const ValueKey('error'),
        isDark: isDark,
        onRetry: widget.onRetry ?? _startStream,
      ),
      _ => _Placeholder(
        key: const ValueKey('placeholder'),
        isOnline: widget.isOnline,
        isDark: isDark,
        onRetry: widget.onRetry ?? _startStream,
      ),
    };
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Stream state enum
// ════════════════════════════════════════════════════════════════════════════
enum _StreamState { idle, connecting, streaming, error }

// ════════════════════════════════════════════════════════════════════════════
//  Sub-widgets
// ════════════════════════════════════════════════════════════════════════════

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE41E3F),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE41E3F).withValues(alpha: 0.55),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7, height: 7,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'LIVE',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectingView extends StatelessWidget {
  final bool isDark;
  const _ConnectingView({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF0F172A), Color(0xFF064E3B)]
              : const [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 36, height: 36,
            child: CircularProgressIndicator(
              color: Color(0xFF00A36C),
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Connecting to camera…',
            style: GoogleFonts.plusJakartaSans(
              color: isDark ? Colors.white70 : const Color(0xFF475569),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Establishing secure tunnel',
            style: GoogleFonts.plusJakartaSans(
              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final bool isDark;
  final VoidCallback onRetry;
  const _ErrorView({super.key, required this.isDark, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF0F172A), Color(0xFF1C1917)]
              : const [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.wifiOff,
            color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            'Stream interrupted',
            style: GoogleFonts.plusJakartaSans(
              color: isDark ? Colors.white60 : const Color(0xFF475569),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Reconnecting in 3 s…',
            style: GoogleFonts.plusJakartaSans(
              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 14, color: Color(0xFF00A36C)),
            label: Text(
              'Retry Now',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFF00A36C),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final bool isOnline;
  final bool isDark;
  final VoidCallback onRetry;
  const _Placeholder({super.key, required this.isOnline, required this.isDark, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final bgColors = isOnline
        ? (isDark
            ? const [Color(0xFF0F172A), Color(0xFF064E3B), Color(0xFF022C22)]
            : const [Color(0xFFECFDF5), Color(0xFFD1FAE5), Color(0xFFA7F3D0)])
        : (isDark
            ? const [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0F172A)]
            : const [Color(0xFFE2E8F0), Color(0xFFCBD5E1), Color(0xFFE2E8F0)]);

    final circleBg = isOnline
        ? const Color(0xFF00A36C).withValues(alpha: isDark ? 0.18 : 0.14)
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFF475569).withValues(alpha: 0.15));

    final circleBorder = isOnline
        ? const Color(0xFF00A36C).withValues(alpha: isDark ? 0.4 : 0.35)
        : (isDark
            ? Colors.white.withValues(alpha: 0.12)
            : const Color(0xFF475569).withValues(alpha: 0.25));

    final iconColor = isOnline
        ? (isDark ? const Color(0xFF10B981) : const Color(0xFF00A36C))
        : (isDark ? Colors.grey.shade400 : const Color(0xFF475569));

    final titleColor    = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF475569);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bgColors,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: circleBg,
              shape: BoxShape.circle,
              border: Border.all(color: circleBorder, width: 2),
              boxShadow: isOnline
                  ? [
                      BoxShadow(
                        color: const Color(0xFF00A36C)
                            .withValues(alpha: isDark ? 0.25 : 0.18),
                        blurRadius: 22,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: Icon(
              isOnline ? LucideIcons.video : LucideIcons.videoOff,
              size: 40,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isOnline ? 'Raspberry Pi Camera Connected' : 'Camera Standby',
            style: GoogleFonts.plusJakartaSans(
              color: titleColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Text(
              isOnline
                  ? 'Stream is initializing…'
                  : 'Waiting for camera connection or dispensing event…',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                color: subtitleColor,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
          if (isOnline) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 14, color: Color(0xFF00A36C)),
              label: Text(
                'Reconnect Stream',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFF00A36C),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
