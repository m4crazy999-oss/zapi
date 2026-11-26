import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ZapiListSkeleton extends StatefulWidget {
  const ZapiListSkeleton({
    super.key,
    this.itemCount = 8,
    this.showTimestamp = true,
  });

  final int itemCount;
  final bool showTimestamp;

  @override
  State<ZapiListSkeleton> createState() => _ZapiListSkeletonState();
}

class _ZapiListSkeletonState extends State<ZapiListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? AppColors.darkSurfaceAlt : const Color(0xFFE6ECEA);
    final highlightColor =
        isDark ? const Color(0xFF283841) : const Color(0xFFF2F6F5);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final fillColor = Color.lerp(baseColor, highlightColor, _controller.value)!;
        return ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: widget.itemCount,
          separatorBuilder: (_, __) => const Divider(indent: 78),
          itemBuilder: (context, index) {
            final titleWidthFactor = index.isEven ? 0.48 : 0.60;
            final subtitleWidthFactor = index % 3 == 0 ? 0.72 : 0.54;
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
                            if (widget.showTimestamp)
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
      },
    );
  }
}
