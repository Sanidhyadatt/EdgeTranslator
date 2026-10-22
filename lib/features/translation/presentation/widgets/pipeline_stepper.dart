import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/pipeline_state.dart';

/// Horizontal visual indicator showing the live state of the speech pipeline.
class PipelineStepper extends StatelessWidget {
  final PipelineStep currentStep;

  const PipelineStepper({super.key, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStageItem(
            label: 'REC',
            icon: Icons.mic,
            isActive: currentStep == PipelineStep.recording,
          ),
          _buildConnector(isActive: currentStep.index >= PipelineStep.speechToText.index),
          _buildStageItem(
            label: 'ASR',
            icon: Icons.graphic_eq,
            isActive: currentStep == PipelineStep.speechToText,
          ),
          _buildConnector(isActive: currentStep.index >= PipelineStep.translation.index),
          _buildStageItem(
            label: 'NMT',
            icon: Icons.translate,
            isActive: currentStep == PipelineStep.translation,
          ),
          _buildConnector(isActive: currentStep.index >= PipelineStep.textToSpeech.index),
          _buildStageItem(
            label: 'TTS',
            icon: Icons.volume_up,
            isActive: currentStep == PipelineStep.textToSpeech || currentStep == PipelineStep.playing,
          ),
        ],
      ),
    );
  }

  Widget _buildStageItem({
    required String label,
    required IconData icon,
    required bool isActive,
  }) {
    final activeColor = AppTheme.primaryNeon;
    final inactiveColor = AppTheme.textMuted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? activeColor.withValues(alpha: 0.2) : Colors.transparent,
            border: Border.all(
              color: isActive ? activeColor : AppTheme.cardBorder,
              width: isActive ? 2 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? activeColor : inactiveColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? activeColor : inactiveColor,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildConnector({required bool isActive}) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryNeon : AppTheme.cardBorder,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
