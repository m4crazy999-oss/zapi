import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ZapiListSkeleton extends StatelessWidget {
  const ZapiListSkeleton({
    super.key,
    this.itemCount = 7,
    this.showTimestamp = true,
  });

  final int itemCount;
  final bool showTimestamp;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? AppColors.darkSurfaceAlt : const Color(0xFFE9EFED);

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const Divider(indent: 78),
      itemBuilder: (context, index) {
        final titleWidthFactor = index.isEven ? 0.46 : 0.58;
        final subtitleWidthFactor = index % 3 == 0 ? 0.70 : 0.52;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: fillColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: titleWidthFactor,
                            child: Container(
                              height: 14,
                              decoration: BoxDecoration(
                                color: fillColor,
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                        ),
                        if (showTimestamp)
                          Container(
                            width: 38,
                            height: 11,
                            decoration: BoxDecoration(
                              color: fillColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: subtitleWidthFactor,
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: fillColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
