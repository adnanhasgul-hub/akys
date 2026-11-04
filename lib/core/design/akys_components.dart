import 'package:flutter/material.dart';

import 'clinical_teal_theme.dart';

class AkysAppScaffold extends StatelessWidget {
  const AkysAppScaffold({
    required this.body,
    this.actions = const [],
    this.title,
    super.key,
  });
  final Widget body;
  final List<Widget> actions;
  final Widget? title;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: title, actions: actions),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AkysTokens.maxContent),
          child: body,
        ),
      ),
    ),
  );
}

class AkysPageHeader extends StatelessWidget {
  const AkysPageHeader({
    required this.title,
    this.description,
    this.actions = const [],
    super.key,
  });
  final String title;
  final String? description;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.headlineLarge),
      ),
      if (description != null) ...[
        const SizedBox(height: AkysTokens.spaceSm),
        Text(description!, style: Theme.of(context).textTheme.bodyLarge),
      ],
      if (actions.isNotEmpty) ...[
        const SizedBox(height: AkysTokens.spaceMd),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    ],
  );
}

class AkysSectionHeader extends StatelessWidget {
  const AkysSectionHeader({required this.title, this.description, super.key});
  final String title;
  final String? description;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (description != null)
        Text(description!, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}

class AkysCard extends StatelessWidget {
  const AkysCard({
    required this.child,
    this.onTap,
    this.semanticLabel,
    super.key,
  });
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: onTap == null
        ? Padding(
            padding: const EdgeInsets.all(AkysTokens.spaceLg),
            child: child,
          )
        : Semantics(
            button: true,
            label: semanticLabel,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AkysTokens.radiusMd),
              child: Padding(
                padding: const EdgeInsets.all(AkysTokens.spaceLg),
                child: child,
              ),
            ),
          ),
  );
}

class AkysStatCard extends StatelessWidget {
  const AkysStatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.description,
    super.key,
  });
  final String label, value;
  final IconData icon;
  final String? description;
  @override
  Widget build(BuildContext context) => AkysCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AkysTokens.primary),
        const SizedBox(height: AkysTokens.spaceSm),
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label),
        if (description != null)
          Text(description!, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class AkysPrimaryButton extends StatelessWidget {
  const AkysPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        if (icon != null) Icon(icon, size: 20),
        Text(label, textAlign: TextAlign.center),
      ],
    ),
  );
}

class AkysSecondaryButton extends StatelessWidget {
  const AkysSecondaryButton({
    required this.label,
    required this.onPressed,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    child: Text(label, textAlign: TextAlign.center),
  );
}

enum AkysStatus { success, warning, error, info, disabled }

class AkysStatusChip extends StatelessWidget {
  const AkysStatusChip({required this.label, required this.status, super.key});
  final String label;
  final AkysStatus status;
  static (Color, Color, IconData) tokens(AkysStatus s) => switch (s) {
    AkysStatus.success => (
      AkysTokens.success,
      AkysTokens.successSurface,
      Icons.check_circle_outline,
    ),
    AkysStatus.warning => (
      AkysTokens.warningText,
      AkysTokens.warning,
      Icons.warning_amber_rounded,
    ),
    AkysStatus.error => (
      AkysTokens.error,
      AkysTokens.errorSurface,
      Icons.error_outline,
    ),
    AkysStatus.info => (
      AkysTokens.info,
      AkysTokens.infoSurface,
      Icons.info_outline,
    ),
    AkysStatus.disabled => (
      AkysTokens.disabled,
      AkysTokens.disabledSurface,
      Icons.schedule,
    ),
  };
  @override
  Widget build(BuildContext context) {
    final (fg, bg, icon) = tokens(status);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AkysTokens.radiusSm),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(icon, color: fg, size: 20),
                Text(
                  label,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AkysEmptyState extends StatelessWidget {
  const AkysEmptyState({
    required this.title,
    required this.message,
    this.action,
    this.icon = Icons.inbox_outlined,
    super.key,
  });
  final String title, message;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AkysTokens.spaceLg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: AkysTokens.muted),
        const SizedBox(height: AkysTokens.spaceMd),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AkysTokens.spaceSm),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[
          const SizedBox(height: AkysTokens.spaceMd),
          action!,
        ],
      ],
    ),
  );
}

class AkysErrorState extends StatelessWidget {
  const AkysErrorState({required this.message, this.onRetry, super.key});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: AkysEmptyState(
      title: 'İşlem tamamlanamadı',
      message: message,
      icon: Icons.error_outline,
      action: onRetry == null
          ? null
          : AkysSecondaryButton(label: 'Yeniden Dene', onPressed: onRetry),
    ),
  );
}

class AkysLoadingState extends StatelessWidget {
  const AkysLoadingState({this.label = 'Yükleniyor', super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.all(AkysTokens.spaceLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(semanticsLabel: label),
          const SizedBox(height: AkysTokens.spaceMd),
          Text(label),
        ],
      ),
    ),
  );
}

class AkysFormField extends StatelessWidget {
  const AkysFormField({
    required this.label,
    this.controller,
    this.validator,
    this.helperText,
    this.enabled = true,
    this.keyboardType,
    this.onSubmitted,
    super.key,
  });
  final String label;
  final String? helperText;
  final TextEditingController? controller;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    validator: validator,
    enabled: enabled,
    keyboardType: keyboardType,
    onFieldSubmitted: onSubmitted,
    decoration: InputDecoration(labelText: label, helperText: helperText),
  );
}

class AkysConfirmDialog extends StatelessWidget {
  const AkysConfirmDialog({
    required this.title,
    required this.message,
    this.confirmLabel = 'Onayla',
    super.key,
  });
  final String title, message, confirmLabel;
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Onayla',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AkysConfirmDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: SingleChildScrollView(child: Text(message)),
    actions: [
      AkysSecondaryButton(
        label: 'Vazgeç',
        onPressed: () => Navigator.pop(context, false),
      ),
      AkysPrimaryButton(
        label: confirmLabel,
        onPressed: () => Navigator.pop(context, true),
      ),
    ],
  );
}
