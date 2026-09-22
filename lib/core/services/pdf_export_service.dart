import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'notes_parser.dart';

/// Lecture notes as a PDF, laid out like the app: what not to miss first,
/// then assignments, quizzes, tasks, key concepts and dates, each in its own
/// block. Notes that did not follow the expected shape are printed as they
/// were written.
class PdfExportService {
  static const MethodChannel _channel = MethodChannel('com.lecto.lecto/audio');

  // The app's palette, for print.
  static final _coral = PdfColor.fromHex('#F16743');
  static final _coralTint = PdfColor.fromHex('#FCEEE8');
  static final _ink = PdfColor.fromHex('#1C1917');
  static final _muted = PdfColor.fromHex('#7C756D');
  static final _border = PdfColor.fromHex('#EFE8DE');
  static final _pinkTint = PdfColor.fromHex('#FFEBF0');
  static final _pinkInk = PdfColor.fromHex('#97245C');
  static final _skyTint = PdfColor.fromHex('#E1F1FF');
  static final _skyInk = PdfColor.fromHex('#16528E');
  static final _examInk = PdfColor.fromHex('#231D1A');
  static final _examAmber = PdfColor.fromHex('#FFC857');
  static final _mintTint = PdfColor.fromHex('#DCF7EA');
  static final _mintInk = PdfColor.fromHex('#0E6245');
  static final _lavTint = PdfColor.fromHex('#EFEAFF');
  static final _lavInk = PdfColor.fromHex('#47368B');
  static final _creamTint = PdfColor.fromHex('#FEF4DC');
  static final _creamInk = PdfColor.fromHex('#A66E0A');

  static Future<Uint8List> generatePdf({
    required String title,
    String? subjectName,
    DateTime? recordingDate,
    Duration? duration,
    required String summaryMarkdown,
    String? transcriptMarkdown,
    bool includeTranscript = false,
  }) async {
    // Noto Sans rather than the PDF's built-in Helvetica, which only knows
    // basic Latin: lecture notes are full of dashes, Greek and maths signs
    // (λ, −, ⁻¹) that Helvetica prints as empty boxes.
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
    final pdf = pw.Document(
      title: title,
      theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: regular),
    );

    final notes = NotesParser.parse(summaryMarkdown);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
        header: (context) => context.pageNumber == 1
            ? _buildHeader(
                title: title,
                subjectName: subjectName,
                recordingDate: recordingDate,
                duration: duration,
              )
            : pw.SizedBox(),
        footer: _buildFooter,
        build: (context) {
          final widgets = notes.isStructured
              ? _structured(notes)
              : _parseMarkdown(summaryMarkdown, _coral);

          if (includeTranscript &&
              transcriptMarkdown != null &&
              transcriptMarkdown.isNotEmpty) {
            widgets
              ..add(pw.NewPage())
              ..add(_sectionTitle('Full transcript', _coral))
              ..add(pw.SizedBox(height: 8))
              ..addAll(
                _parseMarkdown(transcriptMarkdown, _coral, isTranscript: true),
              );
          }
          return widgets;
        },
      ),
    );

    return pdf.save();
  }

  static List<pw.Widget> _structured(ParsedNotes notes) {
    final out = <pw.Widget>[];

    if (notes.important.isNotEmpty) {
      out.add(
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          margin: const pw.EdgeInsets.only(bottom: 14),
          decoration: pw.BoxDecoration(
            color: _coral,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                "DON'T MISS",
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 6),
              for (final item in notes.important)
                _bulletLine(item.replaceAll('**', ''), PdfColors.white),
            ],
          ),
        ),
      );
    }

    if (notes.summary != null) {
      out.add(
        _block('Summary', _coralTint, _coral, [
          pw.Text(
            notes.summary!,
            style: pw.TextStyle(fontSize: 11, lineSpacing: 3, color: _ink),
          ),
        ]),
      );
    }

    if (notes.assignments.isNotEmpty) {
      out.add(
        _block('Assignments', _pinkTint, _pinkInk, [
          for (final a in notes.assignments)
            _checkItem(
              a.text,
              done: a.done,
              sub: [
                if (a.due != null) 'Due ${_date(a.due!)}',
                ?a.details,
              ].join(' · '),
              accent: _pinkInk,
            ),
        ]),
      );
    }

    if (notes.quizzes.isNotEmpty) {
      out.add(
        _block('Quizzes & exams', _skyTint, _skyInk, [
          for (final q in notes.quizzes)
            _datedItem(q.date, q.title, q.details, _skyInk),
        ]),
      );
    }

    if (notes.examHints.isNotEmpty) {
      out.add(
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          margin: const pw.EdgeInsets.only(bottom: 14),
          decoration: pw.BoxDecoration(
            color: _examInk,
            borderRadius: pw.BorderRadius.circular(10),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'EXAM HINTS',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1,
                  color: _examAmber,
                ),
              ),
              pw.SizedBox(height: 6),
              for (final item in notes.examHints)
                _bulletLine(item.replaceAll('**', ''), PdfColors.white),
            ],
          ),
        ),
      );
    }

    if (notes.tasks.isNotEmpty) {
      out.add(
        _block('Tasks', _mintTint, _mintInk, [
          for (final t in notes.tasks)
            _checkItem(t.text, done: t.done, accent: _mintInk),
        ]),
      );
    }

    // Long, so laid out straight on the page rather than in one block that
    // could not break across pages.
    if (notes.lectureNotes != null) {
      out
        ..add(_sectionTitle('Lecture notes', _coral))
        ..add(pw.SizedBox(height: 6))
        ..addAll(_parseMarkdown(notes.lectureNotes!, _coral))
        ..add(pw.SizedBox(height: 14));
    }

    if (notes.concepts.isNotEmpty) {
      out.add(
        _block('Key concepts', _lavTint, _lavInk, [
          for (var i = 0; i < notes.concepts.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 18,
                    child: pw.Text(
                      '${i + 1}.',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _lavInk,
                      ),
                    ),
                  ),
                  pw.Expanded(child: _parseRichText(notes.concepts[i])),
                ],
              ),
            ),
        ]),
      );
    }

    if (notes.deadlines.isNotEmpty) {
      out.add(
        _block('Other dates', _creamTint, _creamInk, [
          for (final d in notes.deadlines)
            _datedItem(d.date, d.description, null, _creamInk),
        ]),
      );
    }

    for (final section in notes.extraSections) {
      out.add(
        _block(
          section.title.isEmpty ? 'Also in the notes' : section.title,
          PdfColors.white,
          _muted,
          _parseMarkdown(section.body, _coral),
          bordered: true,
        ),
      );
    }

    return out;
  }

  /// A tinted section with a small capitalised label.
  static pw.Widget _block(
    String label,
    PdfColor tint,
    PdfColor ink,
    List<pw.Widget> children, {
    bool bordered = false,
  }) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: tint,
        borderRadius: pw.BorderRadius.circular(10),
        border: bordered ? pw.Border.all(color: _border) : null,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionTitle(label.toUpperCase(), ink, small: true),
          pw.SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  static pw.Widget _sectionTitle(
    String text,
    PdfColor color, {
    bool small = false,
  }) => pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: small ? 9 : 16,
      letterSpacing: small ? 1 : 0,
      fontWeight: pw.FontWeight.bold,
      color: color,
    ),
  );

  static pw.Widget _bulletLine(String text, PdfColor color) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 4, right: 7),
          width: 4,
          height: 4,
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
        ),
        pw.Expanded(
          child: pw.Text(
            text,
            style: pw.TextStyle(fontSize: 11, lineSpacing: 2, color: color),
          ),
        ),
      ],
    ),
  );

  static pw.Widget _checkItem(
    String text, {
    required bool done,
    required PdfColor accent,
    String sub = '',
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 1, right: 8),
            width: 10,
            height: 10,
            decoration: pw.BoxDecoration(
              color: done ? accent : PdfColors.white,
              border: pw.Border.all(color: accent, width: 1),
              borderRadius: pw.BorderRadius.circular(2),
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  text,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: done ? _muted : _ink,
                    decoration: done ? pw.TextDecoration.lineThrough : null,
                  ),
                ),
                if (sub.isNotEmpty)
                  pw.Text(
                    sub,
                    style: pw.TextStyle(fontSize: 9.5, color: accent),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _datedItem(
    DateTime? date,
    String title,
    String? details,
    PdfColor ink,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 62,
            child: pw.Text(
              date == null ? 'Date TBC' : _date(date),
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: ink,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                if (details != null)
                  pw.Text(
                    details,
                    style: pw.TextStyle(fontSize: 9.5, color: _muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static pw.Widget _buildHeader({
    required String title,
    String? subjectName,
    DateTime? recordingDate,
    Duration? duration,
  }) {
    final meta = [
      ?subjectName,
      if (recordingDate != null) _date(recordingDate),
      if (duration != null && duration.inMinutes > 0)
        '${duration.inMinutes} min',
    ].join('  ·  ');

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _border, width: 1)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'LECTO NOTES',
            style: pw.TextStyle(
              fontSize: 9,
              letterSpacing: 1.5,
              fontWeight: pw.FontWeight.bold,
              color: _coral,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          if (meta.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(meta, style: pw.TextStyle(fontSize: 10.5, color: _muted)),
          ],
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Text(
        'Made with Lecto  ·  ${context.pageNumber}/${context.pagesCount}',
        style: pw.TextStyle(fontSize: 8.5, color: _muted),
      ),
    );
  }

  static List<pw.Widget> _parseMarkdown(
    String text,
    PdfColor mainColor, {
    bool isTranscript = false,
  }) {
    final lines = text.split('\n');
    final widgets = <pw.Widget>[];

    List<List<String>> currentTable = [];

    void flushTable() {
      if (currentTable.isNotEmpty) {
        widgets.add(
          pw.TableHelper.fromTextArray(
            data: currentTable,
            border: pw.TableBorder.all(color: PdfColors.grey400),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(4),
          ),
        );
        widgets.add(pw.SizedBox(height: 8));
        currentTable = [];
      }
    }

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trim();

      // If line is empty, skip, but flush table
      if (line.isEmpty) {
        flushTable();
        widgets.add(pw.SizedBox(height: 4));
        continue;
      }

      // Check for table
      if (line.startsWith('|') && line.endsWith('|')) {
        final cells = line.split('|').skip(1).map((e) => e.trim()).toList();
        if (cells.isNotEmpty) {
          cells.removeLast(); // skip last empty due to trailing |

          // skip separator lines like |---|---|
          if (cells.every((cell) => cell.replaceAll('-', '').isEmpty)) {
            continue;
          }

          currentTable.add(cells);
        }
        continue;
      } else {
        flushTable();
      }

      // Check headings
      if (line.startsWith('# ')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
            child: pw.Text(
              line.substring(2),
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: mainColor,
              ),
            ),
          ),
        );
        continue;
      }
      if (line.startsWith('## ')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
            child: pw.Text(
              line.substring(3),
              style: pw.TextStyle(
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
                color: mainColor,
              ),
            ),
          ),
        );
        continue;
      }
      if (line.startsWith('### ')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
            child: pw.Text(
              line.substring(4),
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: mainColor,
              ),
            ),
          ),
        );
        continue;
      }

      // Check blockquote
      if (line.startsWith('> ')) {
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 4),
            padding: const pw.EdgeInsets.only(left: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(color: mainColor, width: 2),
              ),
            ),
            child: _parseRichText(
              line.substring(2),
              fontSize: isTranscript ? 10 : 11,
            ),
          ),
        );
        continue;
      }

      // Check checkbox
      if (line.startsWith('- [ ] ') ||
          line.startsWith('- [x] ') ||
          line.startsWith('* [ ] ') ||
          line.startsWith('* [x] ')) {
        final isChecked = line.contains('[x]');
        final textPart = line.substring(6);
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 2, right: 6),
                  width: 10,
                  height: 10,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 1),
                    color: isChecked ? PdfColors.black : PdfColors.white,
                  ),
                ),
                pw.Expanded(
                  child: _parseRichText(
                    textPart,
                    fontSize: isTranscript ? 10 : 11,
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // Check bullet
      if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 8),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4, right: 6),
                  child: pw.Container(
                    width: 4,
                    height: 4,
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.black,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: _parseRichText(
                    line.substring(2),
                    fontSize: isTranscript ? 10 : 11,
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // Regular paragraph
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: _parseRichText(line, fontSize: isTranscript ? 10 : 11),
        ),
      );
    }

    flushTable();

    return widgets;
  }

  static pw.Widget _parseRichText(String text, {double fontSize = 11}) {
    final parts = text.split('**');
    if (parts.length == 1) {
      return pw.Text(text, style: pw.TextStyle(fontSize: fontSize));
    }

    final spans = <pw.InlineSpan>[];
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      if (i % 2 == 1) {
        // bold
        spans.add(
          pw.TextSpan(
            text: parts[i],
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: fontSize,
            ),
          ),
        );
      } else {
        // normal
        spans.add(
          pw.TextSpan(
            text: parts[i],
            style: pw.TextStyle(fontSize: fontSize),
          ),
        );
      }
    }

    return pw.RichText(text: pw.TextSpan(children: spans));
  }

  static String generateFilename({
    String? subjectName,
    DateTime? date,
    String? title,
  }) {
    final parts = ['Lecto'];
    if (subjectName != null && subjectName.isNotEmpty) {
      parts.add(subjectName.replaceAll(' ', ''));
    }
    if (date != null) {
      parts.add(
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      );
    }
    if (title != null && title.isNotEmpty) {
      parts.add(title.replaceAll(' ', ''));
    }
    return '${parts.join('_')}.pdf';
  }

  static Future<void> sharePdf(Uint8List pdfBytes, String filename) async {
    await Printing.sharePdf(bytes: pdfBytes, filename: filename);
  }

  /// Save straight into the phone's Downloads folder.
  ///
  /// Returns false where that is not possible (Android 9 and older, which
  /// need a storage permission the app does not ask for) — callers then
  /// fall back to sharing.
  static Future<bool> saveToDownloads(
    Uint8List pdfBytes,
    String filename,
  ) async {
    try {
      final saved = await _channel.invokeMethod<bool>('saveToDownloads', {
        'bytes': pdfBytes,
        'filename': filename,
        'mimeType': 'application/pdf',
      });
      return saved ?? false;
    } on PlatformException catch (e) {
      debugPrint('PdfExport: could not save (${e.code}) ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
