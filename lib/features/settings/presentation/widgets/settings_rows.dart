import 'package:flutter/material.dart';

class SettingsInputRow extends StatelessWidget {
  const SettingsInputRow({
    required this.title,
    required this.description,
    this.value = '',
    this.controller,
    required this.hintText,
    required this.onChanged,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.trailing,
    super.key,
  });

  final String title;
  final String description;
  final String value;
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SettingsRowFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: SettingsTitleBlock(
                  title: title,
                  description: description,
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: controller == null
                ? ValueKey<int>(Object.hash(title, enabled, value.hashCode))
                : null,
            controller: controller,
            initialValue: controller == null ? value : null,
            enabled: enabled,
            obscureText: obscureText,
            keyboardType: keyboardType,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              filled: true,
              fillColor: enabled ? Colors.white : const Color(0xFFF3F6F4),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFB9CDBE)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFB9CDBE)),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFD4DDD7)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    required this.title,
    required this.description,
    required this.onTap,
    this.danger = false,
    this.icon,
    super.key,
  });

  final String title;
  final String description;
  final VoidCallback onTap;
  final bool danger;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color titleColor = danger
        ? const Color(0xFFC62828)
        : const Color(0xFF191C1E);
    final Color descColor = danger
        ? const Color(0xFFD86A6A)
        : const Color(0xFF53625A);
    final Color iconColor = danger
        ? const Color(0xFFC62828)
        : const Color(0xFF8C9890);

    return InkWell(
      onTap: onTap,
      child: SettingsRowFrame(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: descColor),
                  ),
                ],
              ),
            ),
            Icon(
              icon ??
                  (danger
                      ? Icons.restore_from_trash_rounded
                      : Icons.chevron_right_rounded),
              color: iconColor,
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsRowFrame extends StatelessWidget {
  const SettingsRowFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: child,
    );
  }
}

class SettingsTitleBlock extends StatelessWidget {
  const SettingsTitleBlock({
    required this.title,
    required this.description,
    super.key,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF191C1E),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          description,
          style: const TextStyle(fontSize: 12, color: Color(0xFF53625A)),
        ),
      ],
    );
  }
}
