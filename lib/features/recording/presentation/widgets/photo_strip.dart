import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/services/photo_capture_service.dart';

/// Horizontal scrolling strip of photos captured during recording.
class PhotoStrip extends StatelessWidget {
  final List<CapturedPhoto> photos;
  final VoidCallback? onViewAll;

  const PhotoStrip({
    super.key,
    required this.photos,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${photos.length} photo${photos.length == 1 ? '' : 's'} captured',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondaryDark,
                ),
              ),
              if (onViewAll != null)
                GestureDetector(
                  onTap: onViewAll,
                  child: const Text(
                    'View All',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              final photo = photos[index];
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: _PhotoThumbnail(photo: photo),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  final CapturedPhoto photo;

  const _PhotoThumbnail({required this.photo});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(photo.filePath),
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 80,
              height: 80,
              color: AppColors.darkSurface,
              child: const Icon(
                Icons.broken_image_rounded,
                color: AppColors.textTertiaryDark,
                size: 24,
              ),
            ),
          ),
        ),
        // Timestamp badge
        Positioned(
          bottom: 4,
          left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              photo.timestampFormatted,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
