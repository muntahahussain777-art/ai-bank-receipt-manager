import 'package:flutter/material.dart';

class PageScroll extends StatelessWidget {
  const PageScroll({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: ListView(
          key: const Key('page-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: children,
        ),
      ),
    );
  }
}
