import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

/// Text input: 56px tall, 12px radius, a single-color accent border on focus
/// (the v1-redesign trade-off; the original gradient border felt loud on
/// every form field).
class KarlshareInput extends StatefulWidget {
  const KarlshareInput({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.textInputAction,
  });

  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  @override
  State<KarlshareInput> createState() => _KarlshareInputState();
}

class _KarlshareInputState extends State<KarlshareInput> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(
      () => setState(() => _focused = _focusNode.hasFocus),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KarlshareColors>()!;
    final radius = BorderRadius.circular(AppConstants.radiusSmall + 4);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: AppConstants.microInteraction,
      curve: AppConstants.easeOutKarlshare,
      height: AppConstants.inputHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.space16),
      decoration: BoxDecoration(
        color: isDark ? colors.surface : colors.surfaceElevated,
        borderRadius: radius,
        border: Border.all(
          color: _focused ? colors.accent : colors.border,
          width: _focused ? 1.5 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: colors.accent.withValues(alpha: 0.18),
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        onChanged: widget.onChanged,
        textInputAction: widget.textInputAction,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: widget.hintText,
          hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colors.textTertiary,
              ),
        ),
      ),
    );
  }
}
