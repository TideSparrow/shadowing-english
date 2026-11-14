import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../shared/presentation/pad/pad_compact.dart';
import 'settings_group_card.dart';

class SettingsSection {
  const SettingsSection({
    required this.label,
    required this.icon,
    required this.content,
  });

  SettingsSection.group({
    required String title,
    String? label,
    required this.icon,
    required List<Widget> children,
  }) : label = label ?? title,
       content = SettingsGroupCard(
         title: title,
         icon: icon,
         children: children,
       );

  final String label;
  final IconData icon;
  final Widget content;
}

class SettingsSectionNavigation extends StatefulWidget {
  const SettingsSectionNavigation({
    required this.header,
    required this.sections,
    required this.footer,
    super.key,
  });

  final Widget header;
  final List<SettingsSection> sections;
  final Widget footer;

  @override
  State<SettingsSectionNavigation> createState() =>
      _SettingsSectionNavigationState();
}

class _SettingsSectionNavigationState extends State<SettingsSectionNavigation> {
  final ScrollController _controller = ScrollController();
  final Map<String, GlobalKey> _anchors = <String, GlobalKey>{};
  String? _active;
  String? _jumpTarget;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateActiveSection);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateActiveSection() {
    if (_jumpTarget != null || !_controller.hasClients) return;
    final ScrollPosition position = _controller.position;
    if (!position.hasContentDimensions) return;
    String active = widget.sections.first.label;
    final double readingOffset = position.pixels + context.padPagePadding + 16;
    for (final SettingsSection section in widget.sections) {
      final RenderObject? anchor = _anchors[section.label]?.currentContext
          ?.findRenderObject();
      if (anchor == null || !anchor.attached) continue;
      final RenderAbstractViewport viewport = RenderAbstractViewport.of(anchor);
      if (viewport.getOffsetToReveal(anchor, 0).offset > readingOffset) break;
      active = section.label;
    }
    if (active != _active) setState(() => _active = active);
  }

  Future<void> _goToSection(String label) async {
    final BuildContext? anchor = _anchors[label]?.currentContext;
    if (anchor == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _active = label;
      _jumpTarget = label;
    });
    await Scrollable.ensureVisible(
      anchor,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
    if (mounted && _jumpTarget == label) _jumpTarget = null;
  }

  @override
  Widget build(BuildContext context) {
    final double padding = context.padPagePadding;
    final String active =
        widget.sections.any(
          (SettingsSection section) => section.label == _active,
        )
        ? _active!
        : widget.sections.first.label;
    final Widget content = SingleChildScrollView(
      key: const ValueKey<String>('settings-content'),
      controller: _controller,
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          widget.header,
          SizedBox(height: context.padSectionGap),
          for (final SettingsSection section in widget.sections)
            Padding(
              key: _anchors.putIfAbsent(section.label, GlobalKey.new),
              padding: EdgeInsets.only(
                top: 8,
                bottom: context.isPadCompact ? 12 : 16,
              ),
              child: section.content,
            ),
          widget.footer,
        ],
      ),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showSidebar = constraints.maxWidth >= 700;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (showSidebar)
              SizedBox(
                width: 172,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Color(0xFFE1E6DF))),
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(12, padding, 12, padding),
                    child: _directory(active, _goToSection),
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!showSidebar)
                    Padding(
                      padding: EdgeInsets.fromLTRB(padding, 8, padding, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.list_rounded),
                          label: const Text('设置目录'),
                          onPressed: () async {
                            final String? section =
                                await showModalBottomSheet<String>(
                                  context: context,
                                  useSafeArea: true,
                                  showDragHandle: true,
                                  builder: (BuildContext context) =>
                                      SingleChildScrollView(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          0,
                                          16,
                                          24,
                                        ),
                                        child: _directory(
                                          active,
                                          Navigator.of(context).pop,
                                        ),
                                      ),
                                );
                            if (mounted && section != null) {
                              await _goToSection(section);
                            }
                          },
                        ),
                      ),
                    ),
                  Expanded(child: content),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _directory(String active, ValueChanged<String> onSelect) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (final SettingsSection section in widget.sections)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Semantics(
            selected: section.label == active,
            child: TextButton(
              key: ValueKey<String>('settings-section-${section.label}'),
              onPressed: () => onSelect(section.label),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: section.label == active
                    ? const Color(0xFF0F6C3C)
                    : const Color(0xFF394A40),
                backgroundColor: section.label == active
                    ? const Color(0xFFE4F3E9)
                    : null,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(section.icon, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      section.label,
                      style: TextStyle(
                        fontWeight: section.label == active
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
