import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/chat_message.dart';

enum _HistoryFilter { all, enToJa, jaToEn }

/// Functional History view obeying the active UI instruction language mode.
class HistoryView extends StatefulWidget {
  final AppStrings strings;
  final List<ChatMessage> messages;
  final ValueChanged<ChatMessage> onOpenInTranslate;
  final ValueChanged<String> onPlayTranslation;
  final ValueChanged<ChatMessage> onOpenFullscreen;
  final VoidCallback onClearAll;

  const HistoryView({
    super.key,
    required this.strings,
    required this.messages,
    required this.onOpenInTranslate,
    required this.onPlayTranslation,
    required this.onOpenFullscreen,
    required this.onClearAll,
  });

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = widget.messages.reversed.where((msg) {
      if (_filter == _HistoryFilter.enToJa &&
          msg.sourceLang != TranslationLanguage.english) {
        return false;
      }
      if (_filter == _HistoryFilter.jaToEn &&
          msg.sourceLang != TranslationLanguage.japanese) {
        return false;
      }
      if (normalizedQuery.isNotEmpty) {
        return msg.originalText.toLowerCase().contains(normalizedQuery) ||
            msg.translatedText.toLowerCase().contains(normalizedQuery);
      }
      return true;
    }).toList();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 512),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        s.historyTitle,
                        style: s.isJa
                            ? AppTheme.minchoStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.sumi,
                              )
                            : AppTheme.sansStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.sumi,
                              ),
                      ),
                      const Spacer(),
                      if (widget.messages.isNotEmpty)
                        TextButton.icon(
                          onPressed: widget.onClearAll,
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.cinnabarDeep,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: Text(s.clearButton),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.washiCard.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.lineSubtle),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: AppTheme.sumiMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (v) => setState(() => _query = v),
                            style: AppTheme.sansStyle(
                              fontSize: 14,
                              color: AppTheme.sumi,
                            ),
                            decoration: InputDecoration(
                              hintText: s.searchPlaceholder,
                              hintStyle: AppTheme.sansStyle(
                                fontSize: 13,
                                color: AppTheme.sumiMuted.withValues(alpha: 0.75),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 11),
                            ),
                          ),
                        ),
                        if (_query.isNotEmpty)
                          IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded, size: 16),
                            color: AppTheme.sumiMuted,
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: s.filterAll(widget.messages.length),
                          selected: _filter == _HistoryFilter.all,
                          onTap: () =>
                              setState(() => _filter = _HistoryFilter.all),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: s.filterEnToJa,
                          selected: _filter == _HistoryFilter.enToJa,
                          onTap: () =>
                              setState(() => _filter = _HistoryFilter.enToJa),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: s.filterJaToEn,
                          selected: _filter == _HistoryFilter.jaToEn,
                          onTap: () =>
                              setState(() => _filter = _HistoryFilter.jaToEn),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.lineSubtle),
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmptyState(s)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      physics: const BouncingScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final msg = filtered[index];
                        final isJaTarget =
                            msg.targetLang == TranslationLanguage.japanese;
                        return Material(
                          color: AppTheme.washiCard.withValues(alpha: 0.93),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: msg.isPlaying
                                  ? AppTheme.cinnabar
                                  : AppTheme.lineSubtle,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => widget.onOpenInTranslate(msg),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        s.directionBadge(msg.sourceLang),
                                        style: AppTheme.sansStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.cinnabar,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _formatTime(msg.timestamp),
                                        style: AppTheme.sansStyle(
                                          fontSize: 11,
                                          color: AppTheme.sumiMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    msg.originalText,
                                    style: AppTheme.sansStyle(
                                      fontSize: 14,
                                      color: AppTheme.sumiMuted,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Divider(
                                    height: 1,
                                    color: AppTheme.lineSubtle,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    msg.translatedText,
                                    style: isJaTarget
                                        ? AppTheme.minchoStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                            height: 1.55,
                                            color: AppTheme.sumi,
                                          )
                                        : AppTheme.sansStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            height: 1.4,
                                            color: AppTheme.sumi,
                                          ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        tooltip: s.copyTooltip,
                                        onPressed: () {
                                          Clipboard.setData(
                                            ClipboardData(
                                              text: msg.translatedText,
                                            ),
                                          );
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(s.copiedSnackbar),
                                              duration:
                                                  const Duration(seconds: 1),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.content_copy_rounded,
                                          size: 17,
                                          color: AppTheme.sumiMuted,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      IconButton(
                                        tooltip: s.expandTooltip,
                                        onPressed: () =>
                                            widget.onOpenFullscreen(msg),
                                        icon: const Icon(
                                          Icons.fullscreen_rounded,
                                          size: 19,
                                          color: AppTheme.sumiMuted,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      const SizedBox(width: 4),
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            widget.onPlayTranslation(msg.id),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: msg.isPlaying
                                              ? AppTheme.cinnabarDeep
                                              : AppTheme.cinnabarLight,
                                          foregroundColor: msg.isPlaying
                                              ? Colors.white
                                              : AppTheme.cinnabar,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          shape: const StadiumBorder(),
                                          minimumSize: const Size(0, 32),
                                        ),
                                        icon: Icon(
                                          msg.isPlaying
                                              ? Icons.stop_rounded
                                              : Icons.volume_up_rounded,
                                          size: 15,
                                        ),
                                        label: Text(
                                          msg.isPlaying
                                              ? s.stopLabel
                                              : s.listenLabel,
                                          style: AppTheme.sansStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: msg.isPlaying
                                                ? Colors.white
                                                : AppTheme.cinnabar,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppStrings s) {
    final isFiltering = _query.isNotEmpty || _filter != _HistoryFilter.all;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: AppTheme.washiCard.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.lineSubtle),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.washiSubtle,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.lineSubtle),
                ),
                child: const Icon(
                  Icons.history_rounded,
                  size: 26,
                  color: AppTheme.sumiMuted,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isFiltering
                    ? s.noMatchingHistoryTitle
                    : s.emptyHistoryTitle,
                textAlign: TextAlign.center,
                style: AppTheme.sansStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.sumi,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isFiltering
                    ? s.noMatchingHistorySubtitle
                    : s.emptyHistorySubtitle,
                textAlign: TextAlign.center,
                style: AppTheme.sansStyle(
                  fontSize: 13,
                  color: AppTheme.sumiMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.cinnabar
              : AppTheme.washiSubtle.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppTheme.cinnabar : AppTheme.lineSubtle,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.sansStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.sumiMuted,
          ),
        ),
      ),
    );
  }
}
