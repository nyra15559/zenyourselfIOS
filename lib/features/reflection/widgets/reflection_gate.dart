// lib/features/reflection/widgets/reflection_gate.dart
// v8 — kompakte Gate-Buttons

import 'package:flutter/material.dart';
import '../../../shared/zen_style.dart';

class ReflectionGate extends StatelessWidget {
  final VoidCallback? onContinue;
  final VoidCallback? onSave;
  final VoidCallback? onDelete;

  const ReflectionGate({
    Key? key,
    this.onContinue,
    this.onSave,
    this.onDelete,
  }) : super(key: key);

  factory ReflectionGate.compact({
    VoidCallback? onContinue,
    VoidCallback? onSave,
    VoidCallback? onDelete,
  }) => ReflectionGate(onContinue: onContinue, onSave: onSave, onDelete: onDelete);

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: ZenColors.deepSage,
        );

    Widget pill(IconData i, String t, VoidCallback? f, {bool filled = false}) {
      final bg = filled ? ZenColors.jade.withOpacity(.12) : ZenColors.surface;
      final side = BorderSide(color: ZenColors.jadeMid.withOpacity(.35), width: .8);
      return InkWell(
        onTap: f,
        borderRadius: const BorderRadius.all(ZenRadii.m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.all(ZenRadii.m),
            border: Border.all(color: side.color, width: side.width),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 16, color: ZenColors.deepSage),
            const SizedBox(width: 6),
            Text(t, style: style),
          ]),
        ),
      );
    }

    return Wrap(
      spacing: 8, runSpacing: 8,
      children: [
        if (onContinue != null) pill(Icons.forward_rounded, 'Weiter reflektieren', onContinue),
        if (onSave != null)     pill(Icons.bookmark_added_rounded, 'Ins Gedankenbuch speichern', onSave, filled: true),
        if (onDelete != null)   pill(Icons.delete_outline, 'Löschen', onDelete),
      ],
    );
  }
}
