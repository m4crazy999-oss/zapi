import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                      ? 'As atualizações de ${group.displayName} voltam para a lista principal.'
                      : 'As atualizações de ${group.displayName} ficam recolhidas em Silenciados.',
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
    final boardAsync = ref.watch(statusBoardProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'status_create_fab',
        onPressed: () => _openCreateStatus(context),
        backgroundColor: AppColors.emerald,
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
              hasRing: myStatuses.isNotEmpty,
              isUnviewed: myStatuses.isNotEmpty,
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
          const Divider(height: 1),
          boardAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 12),
              child: ZapiListSkeleton(showTimestamp: false, itemCount: 4),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Não foi possível carregar os status agora.',
                textAlign: TextAlign.center,
                style: TextStyle(color: secondaryText),
              ),
            ),
            data: (board) {
              if (board.recent.isEmpty &&
                  board.viewed.isEmpty &&
                  board.muted.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 56,
                  ),
                  child: Column(
                    children: [
                      const ZapiMascot(
                        mood: ZapiMascotMood.resting,
                        size: 104,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Nenhuma atualização por aqui',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Quando seus contatos publicarem um status, ele aparece aqui por 24 horas.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: secondaryText,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (board.recent.isNotEmpty) ...[
                    _SectionHeader(title: 'Atualizações recentes'),
                    for (var i = 0; i < board.recent.length; i++)
                      _StatusContactTile(
                        group: board.recent[i],
                        timeLabel: _formatUpdatedTime(
                          board.recent[i].latest.createdAt,
                        ),
                        secondaryText: secondaryText,
                        onTap: () => _openContactStatuses(
                          context,
                          groups: board.recent,
                          initialIndex: i,
                        ),
                        onLongPress: () => _showMuteSheet(
                          context,
                          ref,
                          board.recent[i],
                        ),
                      ),
                  ],
                  if (board.viewed.isNotEmpty) ...[
                    _SectionHeader(title: 'Já visualizados'),
                    for (var i = 0; i < board.viewed.length; i++)
                      _StatusContactTile(
                        group: board.viewed[i],
                        timeLabel: _formatUpdatedTime(
                          board.viewed[i].latest.createdAt,
                        ),
                        secondaryText: secondaryText,
                        onTap: () => _openContactStatuses(
                          context,
                          groups: board.viewed,
                          initialIndex: i,
                        ),
                        onLongPress: () => _showMuteSheet(
                          context,
                          ref,
                          board.viewed[i],
                        ),
                      ),
                  ],
                  if (board.muted.isNotEmpty)
                    Theme(
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent,
                      ),
                      child: ExpansionTile(
                        title: Text(
                          'Silenciados (${board.muted.length})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: secondaryText,
                          ),
                        ),
                        children: [
                          for (var i = 0; i < board.muted.length; i++)
                            Opacity(
                              opacity: 0.65,
                              child: _StatusContactTile(
                                group: board.muted[i],
                                timeLabel: _formatUpdatedTime(
                                  board.muted[i].latest.createdAt,
                                ),
                                secondaryText: secondaryText,
                                onTap: () => _openContactStatuses(
                                  context,
                                  groups: board.muted,
                                  initialIndex: i,
                                ),
                                onLongPress: () => _showMuteSheet(
                                  context,
                                  ref,
                                  board.muted[i],
                                ),
                              ),
                            ),
                        ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color:
              isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
        ),
      ),
    );
  }
}

class _StatusContactTile extends StatelessWidget {
  const _StatusContactTile({
    required this.group,
    required this.timeLabel,
    required this.secondaryText,
    required this.onTap,
    required this.onLongPress,
  });

  final ContactStatusGroup group;
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
        hasRing: true,
        isUnviewed: group.hasUnviewed && !group.isMuted,
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
    required this.hasRing,
    required this.isUnviewed,
  });

  final String displayName;
  final String? photoBase64;
  final String? photoUrl;
  final bool hasRing;
  final bool isUnviewed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatar = ZapiAvatar(
      displayName: displayName,
      photoBase64: photoBase64,
      photoUrl: photoUrl,
      radius: 24,
    );

    if (!hasRing) return avatar;

    final ringColor = isUnviewed
        ? AppColors.emerald
        : (isDark ? AppColors.darkBorder : const Color(0xFFB7C4BF));

    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2.2),
      ),
      child: avatar,
    );
  }
}
