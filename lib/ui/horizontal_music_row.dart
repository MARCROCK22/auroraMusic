import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A bounded music shelf. Native pointer handling keeps vertical wheel events
/// with the surrounding page; Shift + wheel and trackpad x deltas move the row.
class HorizontalMusicRow extends StatefulWidget {
  const HorizontalMusicRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemHeight,
    this.itemWidth = 200,
  });
  final String title;
  final String? subtitle;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double itemHeight;
  final double itemWidth;

  @override
  State<HorizontalMusicRow> createState() => _HorizontalMusicRowState();
}

class _HorizontalMusicRowState extends State<HorizontalMusicRow> {
  final _scroll = ScrollController();
  bool _overflow = false, _back = false, _next = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_update);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _update() {
    if (!mounted ||
        !_scroll.hasClients ||
        !_scroll.position.hasContentDimensions) {
      return;
    }
    final position = _scroll.position;
    final overflow = position.maxScrollExtent > 1;
    final back = position.pixels > position.minScrollExtent + 1;
    final next = position.pixels < position.maxScrollExtent - 1;
    if (overflow != _overflow || back != _back || next != _next) {
      setState(() {
        _overflow = overflow;
        _back = back;
        _next = next;
      });
    }
  }

  void _move(double target) {
    if (!_scroll.hasClients) return;
    final offset = target.clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(offset);
    } else {
      _scroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _move(_scroll.offset - widget.itemWidth - 16);
      case LogicalKeyboardKey.arrowRight:
        _move(_scroll.offset + widget.itemWidth + 16);
      case LogicalKeyboardKey.home:
        _move(0);
      case LogicalKeyboardKey.end:
        _move(_scroll.position.maxScrollExtent);
      default:
        {
          return KeyEventResult.ignored;
        }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    return Focus(
      onKeyEvent: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.subtitle!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_overflow)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Desliza para ver más',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Anterior en ${widget.title}',
                  onPressed: _back
                      ? () => _move(
                          _scroll.offset -
                              _scroll.position.viewportDimension * .8,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Siguiente en ${widget.title}',
                  onPressed: _next
                      ? () => _move(
                          _scroll.offset +
                              _scroll.position.viewportDimension * .8,
                        )
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          const SizedBox(height: 12),
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _update());
              return false;
            },
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
                dragDevices: {
                  ...ScrollConfiguration.of(context).dragDevices,
                  PointerDeviceKind.mouse,
                },
              ),
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: _overflow,
                interactive: true,
                child: SizedBox(
                  height: widget.itemHeight + 16,
                  child: ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: widget.itemCount,
                    itemExtent: widget.itemWidth + 16,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: SizedBox(
                        width: widget.itemWidth,
                        child: widget.itemBuilder(context, index),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
