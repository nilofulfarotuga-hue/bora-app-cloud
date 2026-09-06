import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';

const _privateBuckets = <String>{
  'driver-documents',
  'order-photos',
  'receipts',
  'cleaner-documents',
  'restaurant-documents',
};

class _Resolved {
  const _Resolved(this.bucket, this.path);
  final String bucket;
  final String path;
}

_Resolved? _extract(String raw) {
  if (raw.isEmpty) return null;

  if (!raw.startsWith('http')) {
    for (final bucket in _privateBuckets) {
      final prefix = '$bucket/';
      if (raw.startsWith(prefix)) {
        return _Resolved(bucket, raw.substring(prefix.length));
      }
    }
    return null;
  }

  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  final segs = uri.pathSegments;
  final i = segs.indexOf('object');
  if (i < 0 || i + 2 >= segs.length) return null;
  final after = segs[i + 1];
  if (after != 'sign' && after != 'public' && after != 'authenticated') {
    return null;
  }
  final bucket = segs[i + 2];
  if (!_privateBuckets.contains(bucket)) return null;
  final path = segs.sublist(i + 3).join('/');
  if (path.isEmpty) return null;
  return _Resolved(bucket, path);
}

Future<String?> _signed(_Resolved r) async {
  try {
    return await Supabase.instance.client.storage
        .from(r.bucket)
        .createSignedUrl(r.path, 3600);
  } catch (_) {
    return null;
  }
}

/// Some callers persist bare storage paths (no bucket prefix) — e.g.
/// `upload-restaurant-asset` returns `path` without the bucket name. Prepend
/// the bucket so `_extract` recognizes it as a private-bucket reference;
/// leaves full URLs and already-prefixed paths untouched.
String withPrivateBucketPrefix(String bucket, String rawPathOrUrl) {
  if (rawPathOrUrl.isEmpty ||
      rawPathOrUrl.startsWith('http') ||
      rawPathOrUrl.startsWith('$bucket/')) {
    return rawPathOrUrl;
  }
  return '$bucket/$rawPathOrUrl';
}

/// Re-signs URLs that point to private Supabase buckets (driver-documents,
/// order-photos, receipts). Returns the input unchanged for public-bucket URLs
/// or unparsable strings. Returns null if signing failed.
Future<String?> resolveSignedUrlIfPrivate(String urlOrPath) async {
  if (urlOrPath.isEmpty) return null;
  final r = _extract(urlOrPath);
  if (r == null) return urlOrPath;
  return _signed(r);
}

class PrivateBucketImage extends StatefulWidget {
  const PrivateBucketImage({
    super.key,
    required this.urlOrPath,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderHeight = 160,
  });

  final String urlOrPath;
  final double? height;
  final double? width;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final double placeholderHeight;

  @override
  State<PrivateBucketImage> createState() => _PrivateBucketImageState();
}

class _PrivateBucketImageState extends State<PrivateBucketImage> {
  String? _resolvedUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant PrivateBucketImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urlOrPath != widget.urlOrPath) {
      _loading = true;
      _resolvedUrl = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final r = _extract(widget.urlOrPath);
    if (r == null) {
      if (mounted) {
        setState(() {
          _resolvedUrl = widget.urlOrPath;
          _loading = false;
        });
      }
      return;
    }
    final signed = await _signed(r);
    if (mounted) {
      setState(() {
        _resolvedUrl = signed;
        _loading = false;
      });
    }
  }

  Widget _wrap(Widget child) {
    if (widget.borderRadius == null) return child;
    return ClipRRect(borderRadius: widget.borderRadius!, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height ?? widget.placeholderHeight;
    if (_loading) {
      return _wrap(Container(
        height: h,
        width: widget.width ?? double.infinity,
        color: AppColors.divider.withValues(alpha: 0.3),
        alignment: Alignment.center,
        child: const SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ));
    }
    final url = _resolvedUrl;
    if (url == null || url.isEmpty) {
      return _wrap(Container(
        height: h,
        width: widget.width ?? double.infinity,
        color: AppColors.divider.withValues(alpha: 0.3),
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image,
            color: AppColors.textSecondary, size: 48),
      ));
    }
    return _wrap(Image.network(
      url,
      height: widget.height,
      width: widget.width,
      fit: widget.fit,
      errorBuilder: (_, __, ___) => Container(
        height: h,
        width: widget.width ?? double.infinity,
        color: AppColors.divider.withValues(alpha: 0.3),
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image,
            color: AppColors.textSecondary, size: 48),
      ),
    ));
  }
}

class PrivateBucketCircleAvatar extends StatefulWidget {
  const PrivateBucketCircleAvatar({
    super.key,
    required this.urlOrPath,
    this.radius = 50,
  });

  final String urlOrPath;
  final double radius;

  @override
  State<PrivateBucketCircleAvatar> createState() =>
      _PrivateBucketCircleAvatarState();
}

class _PrivateBucketCircleAvatarState extends State<PrivateBucketCircleAvatar> {
  String? _resolvedUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant PrivateBucketCircleAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urlOrPath != widget.urlOrPath) {
      _loading = true;
      _resolvedUrl = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final r = _extract(widget.urlOrPath);
    if (r == null) {
      if (mounted) {
        setState(() {
          _resolvedUrl = widget.urlOrPath;
          _loading = false;
        });
      }
      return;
    }
    final signed = await _signed(r);
    if (mounted) {
      setState(() {
        _resolvedUrl = signed;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: AppColors.divider.withValues(alpha: 0.3),
        child: SizedBox(
          height: widget.radius * 0.4,
          width: widget.radius * 0.4,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final url = _resolvedUrl;
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: AppColors.divider.withValues(alpha: 0.3),
        child: Icon(Icons.person,
            size: widget.radius, color: AppColors.textSecondary),
      );
    }
    return CircleAvatar(
      radius: widget.radius,
      backgroundImage: NetworkImage(url),
    );
  }
}
