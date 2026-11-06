import 'package:cal_scanner/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Minimal formatting for AI replies: **bold**, headings and bullet lists.
class RichReply extends StatelessWidget {
  final String text;
  const RichReply(this.text, {super.key});

  static final _bold = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');

  List<InlineSpan> _inline(String line, TextStyle base) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _bold.allMatches(line)) {
      if (m.start > last) {
        spans.add(TextSpan(text: line.substring(last, m.start), style: base));
      }
      final isBold = m.group(1) != null;
      spans.add(TextSpan(
        text: isBold ? m.group(1) : m.group(2),
        style: isBold
            ? base.copyWith(fontWeight: FontWeight.w700)
            : base.copyWith(fontStyle: FontStyle.italic),
      ));
      last = m.end;
    }
    if (last < line.length) {
      spans.add(TextSpan(text: line.substring(last), style: base));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: 15, height: 1.4, color: AppColors.kBlack);
    final children = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        children.add(const SizedBox(height: 6));
        continue;
      }
      final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(line.trim());
      final bullet = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(line);
      if (heading != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(TextSpan(
            children: _inline(
              heading.group(1)!,
              base.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          )),
        ));
      } else if (bullet != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(left: 4, top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: base),
              Expanded(
                child: Text.rich(TextSpan(children: _inline(bullet.group(1)!, base))),
              ),
            ],
          ),
        ));
      } else {
        children.add(Text.rich(TextSpan(children: _inline(line, base))));
      }
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
