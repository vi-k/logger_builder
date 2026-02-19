import 'dart:io';

import 'package:ansi_escape_codes/ansi_escape_codes.dart' as ansi;

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
