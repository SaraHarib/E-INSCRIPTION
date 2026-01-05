import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../db/local_db.dart';
import 'inscriptions_list_page.dart';

class InscriptionForm extends StatefulWidget {
  const InscriptionForm({super.key});

  @override
  State<InscriptionForm> createState() => _InscriptionFormState();
}

class _InscriptionFormState extends State<InscriptionForm> {
  final _formKey = GlobalKey<FormState>(); // clé pour alider/reset le formulaire

  // Controllers
  final TextEditingController massarController = TextEditingController();
  final TextEditingController nomFrController = TextEditingController();
  final TextEditingController nomArController = TextEditingController();
  final TextEditingController prenomFrController = TextEditingController();
  final TextEditingController prenomArController = TextEditingController();
  final TextEditingController cinController = TextEditingController();
  final TextEditingController villeFrController = TextEditingController();
  final TextEditingController villeArController = TextEditingController();

  DateTime? birthDate;
  DateTime? bacDate;

  // Image picker
  final ImagePicker _picker = ImagePicker();
  XFile? _bacImage;
  XFile? _cinImage;

  bool _isSubmitting = false;

  @override
  void dispose() {
    // libère les controllers quand on quitte la page (évite memory leak)
    massarController.dispose();
    nomFrController.dispose();
    nomArController.dispose();
    prenomFrController.dispose();
    prenomArController.dispose();
    cinController.dispose();
    villeFrController.dispose();
    villeArController.dispose();
    super.dispose();
  }

  bool isArabicText(String text) {
    // vérifie si le texte est uniquement en arabe (avec espaces)
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final arabicRegex = RegExp(
      r'^[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\s]+$',
    );
    return arabicRegex.hasMatch(trimmed);
  }

  Future<void> _pickImage({
    // ouvre caméra/galerie et stocke l’image choisie (bac ou cin)
    required bool isBac,
    required ImageSource source,
  }) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 70,
    );
    if (picked != null) {
      setState(() {
        if (isBac) {
          _bacImage = picked;
        } else {
          _cinImage = picked;
        }
      });
    }
  }

  String _formatDate(DateTime d) {
    // convertit DateTime en format "YYYY-MM-DD" (pour l’API)

    return "${d.year.toString().padLeft(4, '0')}-"
        "${d.month.toString().padLeft(2, '0')}-"
        "${d.day.toString().padLeft(2, '0')}";
  }

  // ---------------- UI Helpers (Design) ----------------

  Widget _sectionTitle(String title, IconData icon) {
    // petit titre de section avec une icône (UI)
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    // container stylé réutilisable (UI)
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 14),
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
      child: child,
    );
  }

  Widget _imagePickerCard({
    // bloc UI pour choisir une image (caméra/galerie) + afficher preview
    required String title,
    required XFile? image,
    required VoidCallback onCamera,
    required VoidCallback onGallery,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text("Caméra"),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text("Galerie"),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 140,
              width: double.infinity,
              color: const Color(0xFFF3F4F8),
              alignment: Alignment.center,
              child: image == null
                  ? const Text(
                "Aucune image sélectionnée",
                style: TextStyle(color: Colors.black54),
              )
                  : Image.file(
                File(image.path),
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------- Verification UI (Bottom Sheet) ----------

  final Map<String, String> _labels = const {
    "nom_fr": "Nom (FR)",
    "prenom_fr": "Prénom (FR)",
    "nom_ar": "Nom (AR)",
    "prenom_ar": "Prénom (AR)",
    "cin": "CIN",
    "code_massar": "Code Massar",
    "date_naissance": "Date naissance",
    "date_bac": "Date bac",
    "ville_fr": "Ville (FR)",
    "ville_ar": "Ville (AR)",
  };

  void _showVerificationSheet({
    // affiche un bottom sheet qui montre le résultat de vérification (OK/KO) + détails OCR
    required Map<String, dynamic> verification,
    required Map<String, dynamic> ocr,
  }) {
    final entries = verification.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final failed = entries.where((e) => e.value != true).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF7F7FB),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: failed.isEmpty
                                ? Colors.green.withOpacity(0.12)
                                : Colors.orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            failed.isEmpty
                                ? Icons.verified_outlined
                                : Icons.warning_amber_rounded,
                            color: failed.isEmpty ? Colors.green : Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                failed.isEmpty
                                    ? "Tout est validé"
                                    : "Vérification nécessaire",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                failed.isEmpty
                                    ? "Tous les champs correspondent aux documents."
                                    : "${failed.length} champ(s) à vérifier.",
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        // Summary chips grid
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE8EAF2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Résultat de comparaison",
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 10),
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: entries.length,
                                gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: 3.3,
                                ),
                                itemBuilder: (context, index) {
                                  final e = entries[index];
                                  final ok = e.value == true;
                                  final label = _labels[e.key] ?? e.key;

                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: ok
                                          ? Colors.green.withOpacity(0.08)
                                          : Colors.red.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: ok
                                            ? Colors.green.withOpacity(0.35)
                                            : Colors.red.withOpacity(0.35),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          ok
                                              ? Icons.check_circle_outline
                                              : Icons.cancel_outlined,
                                          color: ok ? Colors.green : Colors.red,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            label,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: ok ? Colors.green : Colors.red,
                                            borderRadius:
                                            BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            ok ? "OK" : "KO",
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              if (failed.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                const Divider(height: 1),
                                const SizedBox(height: 10),
                                Text(
                                  "Champs en échec : ${failed.map((e) => _labels[e.key] ?? e.key).join(", ")}",
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // OCR expandable
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE8EAF2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Détails OCR",
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 8),
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                childrenPadding:
                                const EdgeInsets.only(top: 8, bottom: 10),
                                title: const Text(
                                  "Texte OCR - Bac",
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                children: [
                                  _ocrBox((ocr["bac"] ?? "").toString()),
                                ],
                              ),
                              const Divider(height: 1),
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                childrenPadding:
                                const EdgeInsets.only(top: 8, bottom: 10),
                                title: const Text(
                                  "Texte OCR - CIN",
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                children: [
                                  _ocrBox((ocr["cin"] ?? "").toString()),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text("Modifier"),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _submitForm(); // retry
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text("Réessayer"),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _ocrBox(String text) {
    // affiche un texte OCR dans une box stylée
    final content = text.trim().isEmpty ? "—" : text.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAF2)),
      ),
      child: Text(
        content,
        style: const TextStyle(
          height: 1.35,
          fontSize: 13,
          color: Colors.black87,
        ),
      ),
    );
  }

  // ---------------- Submit ----------------

  Future<void> _submitForm() async {
    // valide le formulaire + vérifie images/dates + envoie vers l’API (multipart)
    // si tout OK => enregistre en local (SQLite) + popup succès
    // sinon => affiche la sheet de vérification
    if (_isSubmitting) return;

    if (!_formKey.currentState!.validate()) return;

    if (birthDate == null || bacDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez sélectionner les dates")),
      );
      return;
    }

    if (_bacImage == null || _cinImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Veuillez ajouter les photos du bac et de la CIN"),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final uri = Uri.parse("http://10.0.2.2:8000/api/inscriptions");
      final request = http.MultipartRequest("POST", uri);

      request.fields.addAll({
        "code_massar": massarController.text.trim(),
        "nom_fr": nomFrController.text.trim(),
        "nom_ar": nomArController.text.trim(),
        "prenom_fr": prenomFrController.text.trim(),
        "prenom_ar": prenomArController.text.trim(),
        "date_naissance": _formatDate(birthDate!),
        "date_bac": _formatDate(bacDate!),
        "cin": cinController.text.trim(),
        "ville_fr": villeFrController.text.trim(),
        "ville_ar": villeArController.text.trim(),
      });

      request.files.add(
        await http.MultipartFile.fromPath("bac_image", _bacImage!.path),
      );
      request.files.add(
        await http.MultipartFile.fromPath("cin_image", _cinImage!.path),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        final verification = Map<String, dynamic>.from(data["verification"] ?? {});
        final ocr = Map<String, dynamic>.from(data["ocr"] ?? {});

        final bool allOk = verification.values.every((v) => v == true);

        if (allOk) {
          await LocalDb.instance.insertInscription({
            "code_massar": massarController.text.trim(),
            "nom_fr": nomFrController.text.trim(),
            "nom_ar": nomArController.text.trim(),
            "prenom_fr": prenomFrController.text.trim(),
            "prenom_ar": prenomArController.text.trim(),
            "date_naissance": _formatDate(birthDate!),
            "date_bac": _formatDate(bacDate!),
            "cin": cinController.text.trim(),
            "ville_fr": villeFrController.text.trim(),
            "ville_ar": villeArController.text.trim(),
            "created_at": DateTime.now().toIso8601String(),
          });

          if (!mounted) return;
          await _showSuccessDialog();
        } else {
          if (!mounted) return;
          _showVerificationSheet(verification: verification, ocr: ocr);
        }
      } else {
        debugPrint("Erreur API: ${response.statusCode} - ${response.body}");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur lors de l'envoi du formulaire")),
        );
      }
    } catch (e) {
      debugPrint("Exception: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Erreur réseau")),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ---------------- Widgets ----------------

  @override
  Widget build(BuildContext context) {
    // construit l’UI complète du formulaire (champs + images + bouton envoyer)
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        title: Image.asset(
          'assets/branding/logo_wordmark.png',
          height: 26,
          fit: BoxFit.contain,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: "Voir les inscriptions",
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InscriptionsListPage()),
              );
            },
          ),
        ],
      ),



      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _card(
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.school_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Formulaire d’inscription",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Remplissez les infos puis ajoutez les photos.",
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),

              _sectionTitle("Identité", Icons.person_outline),
              _card(
                child: Column(
                  children: [
                    buildTextField(
                      "Code Massar",
                      massarController,
                      icon: Icons.badge_outlined,
                    ),
                    buildTextField(
                      "CIN",
                      cinController,
                      icon: Icons.credit_card_outlined,
                    ),
                  ],
                ),
              ),

              _sectionTitle("Nom & Prénom", Icons.edit_outlined),
              _card(
                child: Column(
                  children: [
                    buildTextField(
                      "Nom (Français)",
                      nomFrController,
                      icon: Icons.abc,
                    ),
                    buildTextField(
                      "Nom (Arabe)",
                      nomArController,
                      textDirection: TextDirection.rtl,
                      mustBeArabic: true,
                      icon: Icons.language,
                    ),
                    buildTextField(
                      "Prénom (Français)",
                      prenomFrController,
                      icon: Icons.abc_outlined,
                    ),
                    buildTextField(
                      "Prénom (Arabe)",
                      prenomArController,
                      textDirection: TextDirection.rtl,
                      mustBeArabic: true,
                      icon: Icons.language_outlined,
                    ),
                  ],
                ),
              ),

              _sectionTitle("Dates", Icons.calendar_today_outlined),
              _card(
                child: Column(
                  children: [
                    buildDatePicker(
                      "Date de naissance",
                      birthDate,
                          (d) => setState(() => birthDate = d),
                    ),
                    buildDatePicker(
                      "Date d'obtention du bac",
                      bacDate,
                          (d) => setState(() => bacDate = d),
                    ),
                  ],
                ),
              ),

              _sectionTitle("Ville", Icons.location_on_outlined),
              _card(
                child: Column(
                  children: [
                    buildTextField(
                      "Ville (Français)",
                      villeFrController,
                      icon: Icons.location_city_outlined,
                    ),
                    buildTextField(
                      "Ville (Arabe)",
                      villeArController,
                      textDirection: TextDirection.rtl,
                      mustBeArabic: true,
                      icon: Icons.location_on_outlined,
                    ),
                  ],
                ),
              ),

              _sectionTitle("Documents", Icons.document_scanner_outlined),
              _imagePickerCard(
                title: "Photo du baccalauréat",
                image: _bacImage,
                onCamera: () => _pickImage(isBac: true, source: ImageSource.camera),
                onGallery: () => _pickImage(isBac: true, source: ImageSource.gallery),
              ),
              _imagePickerCard(
                title: "Photo de la CIN",
                image: _cinImage,
                onCamera: () => _pickImage(isBac: false, source: ImageSource.camera),
                onGallery: () => _pickImage(isBac: false, source: ImageSource.gallery),
              ),

              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitForm,
                  icon: _isSubmitting
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    _isSubmitting ? "Envoi en cours..." : "Envoyer l'inscription",
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildTextField(
      // construit un champ texte avec validation (obligatoire + arabe si demandé)
      String label,
      TextEditingController controller, {
        TextDirection textDirection = TextDirection.ltr,
        bool mustBeArabic = false,
        IconData? icon,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        textDirection: textDirection,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null ? null : Icon(icon),
          filled: true,
          fillColor: const Color(0xFFF7F7FB),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE8EAF2)),
          ),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return "Champ obligatoire";
          }
          if (mustBeArabic && !isArabicText(value)) {
            return "Veuillez saisir ce champ en arabe uniquement";
          }
          return null;
        },
      ),
    );
  }

  Widget buildDatePicker(
      // construit un sélecteur de date (ouvre showDatePicker)
      String label,
      DateTime? date,
      Function(DateTime) onSelected,
      ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          DateTime? picked = await showDatePicker(
            context: context,
            initialDate: DateTime(2000),
            firstDate: DateTime(1960),
            lastDate: DateTime.now(),
          );
          if (picked != null) onSelected(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.calendar_month_outlined),
            filled: true,
            fillColor: const Color(0xFFF7F7FB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE8EAF2)),
            ),
          ),
          child: Text(
            date == null ? "Sélectionner" : "${date.toLocal()}".split(' ')[0],
            style: TextStyle(
              color: date == null ? Colors.black54 : Colors.black87,
              fontWeight: date == null ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
  Future<void> _showSuccessDialog() async {
    // affiche un dialogue de succès + options (nouveau / voir la liste)
    final theme = Theme.of(context);

    // petit masque CIN pour l'affichage
    String maskedCin(String cin) {
      if (cin.length <= 2) return cin;
      return "${cin.substring(0, 2)}•••••";
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icone en cercle
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 14),

              Text(
                "Inscription réussie",
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),

              const Text(
                "Toutes les informations ont été vérifiées.\nL’inscription est enregistrée sur cet appareil.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, height: 1.35),
              ),

              const SizedBox(height: 14),

              // petit résumé
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8EAF2)),
                ),
                child: Column(
                  children: [
                    _kvRow("Code Massar", massarController.text.trim()),
                    const SizedBox(height: 6),
                    _kvRow("CIN", maskedCin(cinController.text.trim())),
                    const SizedBox(height: 6),
                    _kvRow("Ville", villeFrController.text.trim()),
                  ],
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          actions: [
            // Bouton secondaire
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();

                // reset du formulaire (optionnel)
                _formKey.currentState?.reset();
                massarController.clear();
                nomFrController.clear();
                nomArController.clear();
                prenomFrController.clear();
                prenomArController.clear();
                cinController.clear();
                villeFrController.clear();
                villeArController.clear();
                setState(() {
                  birthDate = null;
                  bacDate = null;
                  _bacImage = null;
                  _cinImage = null;
                });
              },
              child: const Text("Nouveau"),
            ),

            // Bouton principal
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InscriptionsListPage()),
                );
              },
              child: const Text("Voir la liste"),
            ),
          ],
        );
      },
    );
  }

  /// Mini widget “clé : valeur”
  Widget _kvRow(String k, String v) {
    // petit widget “clé : valeur” pour le résumé (dans le dialogue succès)

    return Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            v.isEmpty ? "-" : v,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

}
