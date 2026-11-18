import 'package:core_bloc/overlay/touch_reactive_surface.dart';
import 'package:flutter/material.dart';

class OverlaySnackBar extends StatelessWidget {
  final Color color;
  final IconData? icon;
  final String message;
  final String? title;
  final Color textColor;
  final bool dismissOnTap;
  final bool enableTouchFeedback;

  const OverlaySnackBar(
    this.color,
    this.icon,
    this.message,
    this.title, {
    super.key,
    this.textColor = Colors.white,
    this.dismissOnTap = true,
    this.enableTouchFeedback = false,
  });

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(10));
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: textColor),
            const SizedBox(width: 15),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null && title!.isNotEmpty)
                  Text(
                    title!,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                Text(message, style: TextStyle(color: textColor)),
              ],
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: dismissOnTap
          ? () => ScaffoldMessenger.of(context).hideCurrentSnackBar()
          : null,
      child: enableTouchFeedback
          ? TouchReactiveSurface(
              color: color,
              borderRadius: borderRadius,
              glowOpacity: 0.56,
              rimOpacity: 1.0,
              child: content,
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: borderRadius,
              ),
              child: content,
            ),
    );
  }
}
