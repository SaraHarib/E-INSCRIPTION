import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../db/local_db.dart';

class InscriptionsListPage extends StatefulWidget {
  const InscriptionsListPage({super.key});

  @override
  State<InscriptionsListPage> createState() => _InscriptionsListPageState();
}

class _InscriptionsListPageState extends State<InscriptionsListPage> {
  bool _sortDesc = true; // stocke l’ordre de tri (récent -> ancien)
  String _query = "";// stocke le texte de recherche

  DateTime _parseDate(dynamic value) {
    // convertit une valeur en DateTime (sécurisé même si null/format invalide)
    if (value == null) return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  String _formatDate(dynamic value) {
    // formate une date en "yyyy-MM-dd"
    final dt = _parseDate(value);
    return DateFormat('yyyy-MM-dd').format(dt);
  }

  Future<void> _exportPdf(List<Map<String, dynamic>> inscriptions) async {
    // génère un PDF avec la liste des inscriptions et le partage (Printing.sharePdf)
    if (inscriptions.isEmpty) return;

    final doc = pw.Document();

    final rows = inscriptions.map((insc) {
      final nomComplet =
      "${(insc['prenom_fr'] ?? '').toString()} ${(insc['nom_fr'] ?? '').toString()}"
          .trim();

      return [
        _formatDate(insc['created_at']),
        (insc['code_massar'] ?? '').toString(),
        (insc['cin'] ?? '').toString(),
        nomComplet.isEmpty ? "Sans nom" : nomComplet,
        (insc['ville_fr'] ?? '').toString(),
      ];
    }).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Text(
            "Inscriptions enregistrées",
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            "Export généré le ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}",
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const ["Date", "Massar", "CIN", "Nom complet", "Ville"],
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(1.2),
              1: const pw.FlexColumnWidth(1.4),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(2.2),
              4: const pw.FlexColumnWidth(1.4),
            },
          ),
        ],
      ),
    );

    // Partage natif (Android/iOS) + preview compatible
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: "inscriptions_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf",
    );
  }

  List<Map<String, dynamic>> _applySortAndFilter(List<Map<String, dynamic>> data) {
    // applique le filtre de recherche + tri par date (created_at)
    final q = _query.trim().toLowerCase();

    // Filtre simple (nom, cin, massar, ville)
    var filtered = data.where((insc) {
      if (q.isEmpty) return true;
      final nom =
      "${(insc['prenom_fr'] ?? '')} ${(insc['nom_fr'] ?? '')}".toString().toLowerCase();
      final cin = (insc['cin'] ?? '').toString().toLowerCase();
      final massar = (insc['code_massar'] ?? '').toString().toLowerCase();
      final ville = (insc['ville_fr'] ?? '').toString().toLowerCase();
      return nom.contains(q) || cin.contains(q) || massar.contains(q) || ville.contains(q);
    }).toList();

    // Tri par created_at
    filtered.sort((a, b) {
      final da = _parseDate(a['created_at']);
      final db = _parseDate(b['created_at']);
      return _sortDesc ? db.compareTo(da) : da.compareTo(db);
    });

    return filtered;
  }

  Widget _pill(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // construit toute l’UI de la page (barre recherche/tri/pdf + liste)
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Inscriptions enregistrées"),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: LocalDb.instance.getAllInscriptions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text("Erreur : ${snapshot.error}"),
            );
          }

          final inscriptions = snapshot.data ?? [];
          final viewData = _applySortAndFilter(inscriptions);

          return Column(
            children: [
              // Barre outils (recherche + tri + export)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  children: [
                    _pill(
                      TextField(
                        onChanged: (v) => setState(() => _query = v),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          prefixIcon: Icon(Icons.search),
                          hintText: "Rechercher (nom, CIN, Massar, ville)...",
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _pill(
                            Row(
                              children: [
                                Icon(Icons.sort, color: primary, size: 18),
                                const SizedBox(width: 8),
                                const Text(
                                  "Tri",
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const Spacer(),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<bool>(
                                    value: _sortDesc,
                                    items: const [
                                      DropdownMenuItem(
                                        value: true,
                                        child: Text("Plus récent"),
                                      ),
                                      DropdownMenuItem(
                                        value: false,
                                        child: Text("Plus ancien"),
                                      ),
                                    ],
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setState(() => _sortDesc = v);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: viewData.isEmpty ? null : () => _exportPdf(viewData),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text("PDF"),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        )
                      ],
                    ),
                  ],
                ),
              ),

              // Liste
              Expanded(
                child: viewData.isEmpty
                    ? const Center(
                  child: Text("Aucune inscription enregistrée pour le moment."),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: viewData.length,
                  itemBuilder: (context, index) {
                    final insc = viewData[index];

                    final nomComplet =
                    "${insc['prenom_fr'] ?? ''} ${insc['nom_fr'] ?? ''}".trim();
                    final date = _formatDate(insc['created_at']);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE8EAF2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.center,
                            child: Icon(Icons.person_outline, color: primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nomComplet.isEmpty ? "Sans nom" : nomComplet,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Massar: ${insc['code_massar'] ?? ''}",
                                  style: const TextStyle(color: Colors.black54),
                                ),
                                Text(
                                  "CIN: ${insc['cin'] ?? ''}",
                                  style: const TextStyle(color: Colors.black54),
                                ),
                                Text(
                                  "Ville: ${insc['ville_fr'] ?? ''}",
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            date,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
