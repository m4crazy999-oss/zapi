import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/chat_preferences_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/shimmer_skeleton.dart';
import '../../../../core/widgets/zapi_avatar.dart';
import '../../../../core/widgets/zapi_mascot.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../domain/status_item.dart';
import '../providers/status_providers.dart';
import 'create_status_screen.dart';
import 'status_privacy_screen.dart';
import 'status_viewer_screen.dart';

class StatusScreen extends ConsumerWidget {
  const StatusScreen({super.key});

  String _formatUpdatedTime(DateTime time) {
    final day = DateFormatter.formatDaySeparator(time).toLowerCase();
    return '$day às ${DateFormatter.formatTime(time)}';
  }

  void _openCreateStatus(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const CreateStatusScreen(),
      ),
    );
  }

  void _openPrivacy(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const StatusPrivacyScreen(),
      ),
    );
  }

  void _openMyStatuses(
    BuildContext context, {
    required String displayName,
    required String username,
    required String? photoBase64,
    required List<StatusItem> myStatuses,
    required String uid,
  }) {
    if (myStatuses.isEmpty) {
      _openCreateStatus(context);
      return;
    }

    final myGroup = ContactStatusGroup(
      ownerUid: uid,
      displayName: displayName,
      username: username,
      photoBase64: photoBase64,
      statuses: myStatuses,
      hasUnviewed: false,
    );

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => StatusViewerScreen(
          groups: [myGroup],
          initialGroupIndex: 0,
          isMine: true,
        ),
      ),
    );
  }

  void _openContactStatuses(
    BuildContext context, {
    required List<ContactStatusGroup> groups,
    required int initialIndex,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => StatusViewerScreen(
          groups: groups,
          initialGroupIndex: initialIndex,
          isMine: false,
        ),
      ),
    );
  }

  Future<void> _showMuteSheet(
    BuildContext context,
    WidgetRef ref,
    ContactStatusGroup group,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  group.isMuted
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                ),
                title: Text(
                  group.isMuted ? 'Reativar status' : 'Silenciar status',
                ),
                subtitle: Text(
                  group.isMuted
                      ? 'As atualizações de ${group.displayName} voltam para o topo na ordem normal.'
                      : 'As atualizações de ${group.displayName} ficam recolhidas no final da lista.',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ref.read(chatPreferencesProvider.notifier).setStatusMuted(
                        group.ownerUid,
                        !group.isMuted,
                      );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final myStatuses = ref.watch(myStatusesProvider);
    final groupsAsync = ref.watch(unifiedStatusGroupsProvider);
    final prefs = ref.watch(chatPreferencesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final accentColor = Theme.of(context).colorScheme.primary;

    final displayName = profile?.displayName ?? 'Meu status';
    final myLatest = myStatuses.isNotEmpty ? myStatuses.last : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Status'),
        actions: [
          IconButton(
            tooltip: 'Privacidade do status',
            onPressed: () => _openPrivacy(context),
            icon: const Icon(Icons.lock_rounded),
          ),
          IconButton(
            tooltip: 'Configurações',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.push('/profile'),
              child: ZapiAvatar(
                displayName: profile?.displayName ?? 'Você',
                photoBase64: profile?.photoBase64,
                photoUrl: profile?.photoUrl,
                radius: 17,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'status_create_fab',
        onPressed: () => _openCreateStatus(context),
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        tooltip: 'Novo status',
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Novo status',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 92),
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            leading: _StatusRingAvatar(
              displayName: displayName,
              photoBase64: profile?.photoBase64,
              photoUrl: profile?.photoUrl,
              segmentsViewed: [
                for (var i = 0; i < myStatuses.length; i++) false,
              ],
              accentColor: accentColor,
            ),
            title: const Text(
              'Meu status',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              myLatest != null
                  ? '${myStatuses.length} ativo${myStatuses.length == 1 ? '' : 's'} · ${_formatUpdatedTime(myLatest.createdAt)}'
                  : 'Toque para publicar texto, foto ou vídeo',
              style: TextStyle(color: secondaryText),
            ),
            trailing: myStatuses.isNotEmpty
                ? const Icon(Icons.chevron_right_rounded)
                : null,
            onTap: () => _openMyStatuses(
              context,
              displayName: displayName,
              username: profile?.username ?? '',
              photoBase64: profile?.photoBase64,
              myStatuses: myStatuses,
              uid: profile?.uid ?? '',
            ),
          ),
          const SizedBox(height: 8),
          groupsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 12),
              child: ZapiListSkeleton(showTimestamp: false, itemCount: 4),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ZapiMascotWithBubble(
                  mood: ZapiMascotMood.waiting,
                  mascotSize: 90,
                  message: 'Ops! Não consegui carregar os status agora.',
                ),
              ),
            ),
            data: (groups) {
              if (groups.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 48,
                  ),
                  child: Center(
                    child: ZapiMascotWithBubble(
                      mood: ZapiMascotMood.resting,
                      mascotSize: 102,
                      message:
                          'Tudo tranquilo! Quando seus contatos postarem um status, ele aparece aqui por 24h.',
                    ),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < groups.length; i++)
                    Opacity(
                      opacity: groups[i].isMuted ? 0.62 : 1.0,
                      child: _StatusContactTile(
                        group: groups[i],
                        segmentsViewed: [
                          for (final s in groups[i].statuses)
                            groups[i].isMuted || prefs.isStatusViewed(s.id),
                        ],
                        accentColor: accentColor,
                        timeLabel: _formatUpdatedTime(
                          groups[i].latest.createdAt,
                        ),
                        secondaryText: secondaryText,
                        onTap: () => _openContactStatuses(
                          context,
                          groups: groups,
                          initialIndex: i,
                        ),
                        onLongPress: () => _showMuteSheet(
                          context,
                          ref,
                          groups[i],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusContactTile extends StatelessWidget {
  const _StatusContactTile({
    required this.group,
    required this.segmentsViewed,
    required this.accentColor,
    required this.timeLabel,
    required this.secondaryText,
    required this.onTap,
    required this.onLongPress,
  });

  final ContactStatusGroup group;
  final List<bool> segmentsViewed;
  final Color accentColor;
  final String timeLabel;
  final Color secondaryText;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final count = group.statuses.length;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _StatusRingAvatar(
        displayName: group.displayName,
        photoBase64: group.photoBase64,
        segmentsViewed: segmentsViewed,
        accentColor: accentColor,
      ),
      title: Text(
        group.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        count > 1 ? '$count atualizações · $timeLabel' : timeLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: secondaryText),
      ),
      trailing: group.isMuted
          ? Icon(
              Icons.notifications_off_rounded,
              size: 16,
              color: secondaryText,
            )
          : null,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

class _StatusRingAvatar extends StatelessWidget {
  const _StatusRingAvatar({
    required this.displayName,
    this.photoBase64,
    this.photoUrl,
    required this.segmentsViewed,
    required this.accentColor,
  });

  final String displayName;
  final String? photoBase64;
  final String? photoUrl;
  final List<bool> segmentsViewed;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatar = ZapiAvatar(
      displayName: displayName,
      photoBase64: photoBase64,
      photoUrl: photoUrl,
      radius: 24,
    );

    if (segmentsViewed.isEmpty) return avatar;

    final viewedColor =
        isDark ? AppColors.darkBorder : const Color(0xFFB7C4BF);

    return CustomPaint(
      painter: _StatusSegmentedRingPainter(
        segmentsViewed: segmentsViewed,
        unviewedColor: accentColor,
        viewedColor: viewedColor,
      ),
      child: Padding(
        padding: const EdgeInsets.all(4.5),
        child: avatar,
      ),
    );
  }
}

class _StatusSegmentedRingPainter extends CustomPainter {
  const _StatusSegmentedRingPainter({
    required this.segmentsViewed,
    required this.unviewedColor,
    required this.viewedColor,
  });

  final List<bool> segmentsViewed;
  final Color unviewedColor;
  final Color viewedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final count = segmentsViewed.length;
    if (count == 0) return;

    const strokeWidth = 2.4;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (count == 1) {
      paint.color = segmentsViewed.first ? viewedColor : unviewedColor;
      canvas.drawArc(arcRect, 0, math.pi * 2, false, paint);
      return;
    }

    final gap = count > 8 ? 0.14 : 0.18;
    final totalSweep = math.pi * 2;
    final segmentSweep = (totalSweep - count * gap) / count;
    var startAngle = -math.pi / 2 + gap / 2;

    for (var i = 0; i < count; i++) {
      paint.color = segmentsViewed[i] ? viewedColor : unviewedColor;
      canvas.drawArc(arcRect, startAngle, segmentSweep, false, paint);
      startAngle += segmentSweep + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _StatusSegmentedRingPainter oldDelegate) {
    if (oldDelegate.unviewedColor != unviewedColor ||
        oldDelegate.viewedColor != viewedColor ||
        oldDelegate.segmentsViewed.length != segmentsViewed.length) {
      return true;
    }
    for (var i = 0; i < segmentsViewed.length; i++) {
      if (oldDelegate.segmentsViewed[i] != segmentsViewed[i]) return true;
    }
    return false;
  }
}
