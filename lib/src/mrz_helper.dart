import 'package:flutter/material.dart';
import 'package:mrz_scanner_plus/src/mrz_parser/mrz_parser.dart';
import 'package:mrz_scanner_plus/src/mrz_parser/mrz_result.dart';

class MRZHelper {
  static List<String>? getFinalListToParse(List<String> ableToScanTextList) {
    if (ableToScanTextList.isEmpty) return null;

    final lineLength = ableToScanTextList.first.length;

    // TD1 needs 3 lines, TD2/TD3 need 2
    final expectedCount = switch (lineLength) {
      30 => 3,
      36 => 2,
      44 => 2,
      _ => null,
    };

    if (expectedCount == null) return null;
    if (ableToScanTextList.length < expectedCount) return null;

    final linesToUse = ableToScanTextList.length > expectedCount
        ? ableToScanTextList.sublist(ableToScanTextList.length - expectedCount)
        : ableToScanTextList;

    for (final e in linesToUse) {
      if (e.length != lineLength) return null;
    }

    final supportedDocTypes = {'A', 'C', 'P', 'V', 'I'};
    if (!supportedDocTypes.contains(linesToUse.first[0])) return null;

    return [...linesToUse];
  }

  static String testTextLine(String text) {
    if (text.contains('<')) {
      text = text
          .replaceAll(' ', '')
          .replaceAll('‹', '<')
          .replaceAll('≪', '<')
          .replaceAll('⪡', '<')
          .replaceAll('«', '<')
          .replaceAll('⟨', '<')
          .replaceAll('<*', '<<')
          .replaceAll('《', '<')
          .replaceAll('<K<', '<<<')
          .replaceAll('<k<', '<<<');

      final index = text.indexOf('<<<');
      if (index > 0) {
        final header = text.substring(0, index);
        final tail = text.substring(index);
        text = '$header${tail.replaceAll('k', '<').replaceAll('K', '<')}';
      }
      text = _ifNotEnough(text);
    }

    final list = text.split('');
    const validLengths = {30, 36, 44};

    if (!validLengths.contains(list.length)) {
      return (text.contains('<') && text.replaceAll('<', '').trim().isNotEmpty)
          ? text
          : '';
    }

    for (var i = 0; i < list.length; i++) {
      if (RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(list[i])) {
        list[i] = list[i].toUpperCase();
      }
      if (double.tryParse(list[i]) == null &&
          !RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(list[i])) {
        list[i] = '<';
      }
    }
    return list.join();
  }

  static MRZResult? parse(String recognizedText) {
    final fullText = recognizedText.trim().replaceAll(' ', '');
    final allText = fullText.split('\n');

    final ableToScanText = <String>[];
    for (final line in allText) {
      final tested = testTextLine(line);
      if (tested.isNotEmpty) {
        ableToScanText.add(tested);
      }
    }

    final mrzLines = _filterAvailableLines(ableToScanText);
    for (final mrzLineGroup in mrzLines) {
      debugPrint('OCR:\n${mrzLineGroup.join('\n')}');
      final lines = getFinalListToParse(mrzLineGroup);
      if (lines != null && lines.isNotEmpty) {
        try {
          final mrzResult = MRZParser.parse(lines);
          debugPrint('$mrzResult');
          return mrzResult;
        } catch (e) {
          debugPrint('Parse attempt failed: $e');
        }
      }
    }
    return null;
  }

  static List<List<String>> _filterAvailableLines(List<String> lines) {
    final availableLines = <List<String>>[];
    final mrz44Lines = <String>[];
    final mrz36Lines = <String>[];
    final mrz30Lines = <String>[];

    var fallback44 = '<';
    var fallback36 = '<';
    var fallback30 = '<';

    for (final line in lines) {
      final length = line.length;
      if (length == 44) {
        mrz44Lines.add(line);
        continue;
      }
      if (length == 36) {
        mrz36Lines.add(line);
        continue;
      }
      if (length == 30) {
        mrz30Lines.add(line);
        continue;
      }
      if (line.contains('<')) {
        final isEmpty = line.replaceAll('<', '').trim().isEmpty;
        if (!isEmpty) {
          if (length > 36) {
            fallback44 = line;
          } else if (length > 30) {
            fallback36 = line;
          } else {
            fallback30 = line;
          }
        }
      }
    }

    // TD3 (44-char, 2 lines)
    if (mrz44Lines.length == 1 && fallback44 != '<') {
      mrz44Lines.insert(0, fallback44 + '<' * (44 - fallback44.length));
    }
    if (mrz44Lines.length >= 2) availableLines.add(mrz44Lines);

    // TD2 (36-char, 2 lines)
    if (mrz36Lines.length == 1 && fallback36 != '<') {
      mrz36Lines.insert(0, fallback36 + '<' * (36 - fallback36.length));
    }
    if (mrz36Lines.length >= 2) availableLines.add(mrz36Lines);

    // TD1 (30-char, 3 lines)
    if (mrz30Lines.length >= 3) {
      final td1Candidate = mrz30Lines.length > 3
          ? mrz30Lines.sublist(mrz30Lines.length - 3)
          : mrz30Lines;
      availableLines.add(td1Candidate);
    }

    return availableLines;
  }

  static String _ifNotEnough(String text) {
    if (text.length > 36 && text.length < 44) {
      return _createEnoughText(44, text);
    }
    if (text.length >= 25 && text.length < 30) {
      return _createEnoughText(30, text);
    }
    if (text.length > 30 && text.length < 36) {
      return _createEnoughText(36, text);
    }
    return text;
  }

  static String _createEnoughText(int length, String text) {
    final leftLength = length - text.length;
    final index = text.indexOf('<');
    if (index < 0) return text + '<' * leftLength;
    final header = text.substring(0, index);
    final tail = text.substring(index);
    return '$header${'<' * leftLength}$tail';
  }
}
