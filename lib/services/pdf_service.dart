import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'dart:developer' as dev;

class PdfService {
  static Future<void> generatePlayerReport({
    required String title,
    required String subTitle,
    required List reportData,
  }) async {
    final pdf = pw.Document();
    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // Asegurarnos que reportData sea una lista real de Dart
    final List cleanReportData = List.from(reportData);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          final List<pw.Widget> widgets = [];

          // Header
          widgets.add(
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      title,
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      subTitle,
                      style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Text(
                  'Fecha: $now',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              ],
            ),
          );
          
          widgets.add(pw.SizedBox(height: 20));
          widgets.add(pw.Divider(thickness: 0.5, color: PdfColors.grey400));
          widgets.add(pw.SizedBox(height: 20));

          // Teams and Players
          for (int i = 0; i < cleanReportData.length; i++) {
            final dynamic team = cleanReportData[i];
            if (team is! Map) continue;

            final String teamName = (team['teamName'] ?? 'Sin Nombre').toString();
            final dynamic playersData = team['players'];
            final List playersList = playersData is Iterable ? List.from(playersData) : [];

            widgets.add(
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'EQUIPO: $teamName',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                    ),
                    pw.Text(
                      '${playersList.length} Jugadores',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
            );
            
            widgets.add(pw.SizedBox(height: 8));
            widgets.add(_buildTable(playersList));
            widgets.add(pw.SizedBox(height: 24));
          }

          return widgets;
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${title.replaceAll(' ', '_')}_Report.pdf',
    );
  }

  static pw.Widget _buildTable(List players) {
    final List<pw.TableRow> rows = [];

    // Header Row
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          _h('#'),
          _h('Nombre Completo'),
          _h('Núm'),
          _h('Estado'),
          _h('Pendiente'),
          _h('Notas'),
        ],
      ),
    );

    // Data Rows
    for (int j = 0; j < players.length; j++) {
      final dynamic p = players[j];
      if (p is! Map) continue;

      final String name = (p['name'] ?? '-').toString();
      final String num = (p['number'] ?? '-').toString();
      final String statusText = (p['statusText'] ?? 'PDTE').toString();
      final String notes = (p['notes'] ?? '').toString();
      final String missing = (p['missing'] ?? '').toString();
      
      PdfColor statusColor = PdfColors.grey600;
      if (statusText == 'APROBADO') statusColor = PdfColors.green700;
      else if (statusText == 'PARCIAL') statusColor = PdfColors.orange700;
      else if (statusText == 'RECHAZADO') statusColor = PdfColors.red700;

      rows.add(
        pw.TableRow(
          children: [
            _c('${j + 1}'),
            _c(name),
            _c(num),
            _c(statusText, color: statusColor, bold: true),
            _c(missing),
            _c(notes),
          ],
        ),
      );
    }

    return pw.Table(
      border: const pw.TableBorder(
        bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
      ),
      columnWidths: {
        0: const pw.FixedColumnWidth(25),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FixedColumnWidth(30),
        3: const pw.FixedColumnWidth(70),
        4: const pw.FlexColumnWidth(2),
        5: const pw.FlexColumnWidth(2),
      },
      children: rows,
    );
  }

  static pw.Widget _h(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      ),
    );
  }

  static pw.Widget _c(String text, {PdfColor? color, bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
