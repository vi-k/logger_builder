import 'dart:io';
import 'dart:math' as math;

import 'package:ansi_escape_codes/ansi_escape_codes.dart' as ansi;
import 'package:ansi_escape_codes/extensions.dart';

final _titlePrinter = ansi.AnsiPrinter(
  ansiCodesEnabled: !Platform.isIOS,
  defaultState: const ansi.SgrPlainState(
    foreground: ansi.Color256(ansi.Colors.rgb530),
  ),
);

final _subtitlePrinter = ansi.AnsiPrinter(
  ansiCodesEnabled: !Platform.isIOS,
  defaultState: const ansi.SgrPlainState(
    foreground: ansi.Color256(ansi.Colors.rgb432),
  ),
);

final _linePrinter = ansi.AnsiPrinter(
  ansiCodesEnabled: !Platform.isIOS,
  defaultState: const ansi.SgrPlainState(
    foreground: ansi.Color256(ansi.Colors.gray16),
  ),
);

final _descriptionPrinter = ansi.AnsiPrinter(
  ansiCodesEnabled: !Platform.isIOS,
  defaultState: const ansi.SgrPlainState(
    foreground: ansi.Color256(ansi.Colors.gray10),
  ),
);

void title(String text) {
  _titlePrinter
    ..print('')
    ..print(_prepare(text));
}

void subtitle(String text) {
  _subtitlePrinter
    ..print('')
    ..print(_prepare(text));
}

void line(String text) {
  _linePrinter.print(_prepare(text));
}

void description(String text) {
  _descriptionPrinter.print(_prepare(text));
}

void box(String text) {
  final lines = text.split('\n');
  final widths = lines.map((line) => line.removeEscapeCodes().length).toList();
  final maxWidth = widths.reduce(math.max);
  _descriptionPrinter.print('┌─${'─' * maxWidth}─┐');
  for (final (index, line) in lines.indexed) {
    _descriptionPrinter
      ..write('│ ')
      ..write('${ansi.fg256Gray10}$line${ansi.reset}')
      ..write(' ' * (maxWidth - widths[index]))
      ..writeln(' │');
  }
  _descriptionPrinter.print('└─${'─' * maxWidth}─┘');
}

String _prepare(String text) => text
    .replaceAllMapped(
      RegExp(r'\[b\](.*?)\[/b\]'),
      (match) => '${ansi.fg256Rgb555}${match.group(1)}${ansi.reset}',
    )
    .replaceAllMapped(
      RegExp(r'\[on\](.*?)\[/on\]'),
      (match) => '${ansi.fg256Rgb141}${match.group(1)}${ansi.reset}',
    )
    .replaceAllMapped(
      RegExp(r'\[err\](.*?)\[/err\]'),
      (match) => '${ansi.fg256Rgb411}${match.group(1)}${ansi.reset}',
    )
    .replaceAllMapped(
      RegExp(r'\[off\](.*?)\[/off\]'),
      (match) => '${ansi.fg256Gray10}${match.group(1)}${ansi.reset}',
    );
