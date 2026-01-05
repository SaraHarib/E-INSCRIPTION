<?php

namespace App\Http\Controllers;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;

class InscriptionController extends Controller
{
    public function store(Request $request)
    {
        // Valide les champs reçus (si invalide => Laravel renvoie une erreur auto)
        $validated = $request->validate([
            'code_massar'    => 'required|string|max:50',
            'nom_fr'         => 'required|string|max:100',
            'nom_ar'         => 'required|string|max:100',
            'prenom_fr'      => 'required|string|max:100',
            'prenom_ar'      => 'required|string|max:100',
            'date_naissance' => 'required|date',
            'date_bac'       => 'required|date',
            'cin'            => 'required|string|max:20',
            'ville_fr'       => 'required|string|max:100',
            'ville_ar'       => 'required|string|max:100',
            'bac_image'      => 'required|image|max:4096',
            'cin_image'      => 'required|image|max:4096',
        ]);

        // Sauvegarde les 2 images envoyées (bac + cin) dans storage/public
        $bacPath = $request->file('bac_image')->store('bacs', 'public');
        $cinPath = $request->file('cin_image')->store('cins', 'public');

        $bacFullPath = storage_path('app/public/' . $bacPath);
        $cinFullPath = storage_path('app/public/' . $cinPath);

        // Lance l’OCR sur l’image du bac et récupère le texte
$ocrBacText = $this->performOcr($bacFullPath, 'ara','eng'); 
        \Log::info("OCR BAC = " . $ocrBacText);


        // Lance l’OCR sur l’image de la CIN et récupère le texte
$ocrCinText = $this->performOcr($cinFullPath, 'ara','eng');
        \Log::info("OCR CIN = " . $ocrCinText);

        // Concatène tout le texte OCR (bac + cin) pour faire les vérifs
        $allText = $ocrBacText . ' ' . $ocrCinText;

        // Garde uniquement le texte arabe (pour comparer nom/prénom/ville en arabe)
$allArabicText = preg_replace('/[^\p{Arabic}\s]+/u', ' ', $allText);


        // Vérification 
       // Compare les champs saisis avec le texte OCR (avec exact/fuzzy/date)

       $verification = [
    'nom_fr'        => $this->containsIgnoreCase($allText, $validated['nom_fr']),
    'prenom_fr'     => $this->containsIgnoreCase($allText, $validated['prenom_fr']),
'cin' => $this->fuzzyAlnumContains($allText, $validated['cin'], 0.8),

    'code_massar'   => $this->fuzzyAlnumContains($ocrBacText, $validated['code_massar'], 0.7),

    'date_naissance'=> $this->dateMatchesOcr($allText, $validated['date_naissance']),
    'date_bac'      => $this->dateMatchesOcr($allText, $validated['date_bac']),

'ville_fr'  => $this->containsIgnoreCase($allText, $validated['ville_fr']),
'ville_ar'  => $this->fuzzyContains($allArabicText, $validated['ville_ar'], 0.8),

    // Arabe 
'nom_ar'    => $this->fuzzyContains($allArabicText, $validated['nom_ar'], 0.5),
'prenom_ar' => $this->fuzzyContains($allArabicText, $validated['prenom_ar'], 0.5),
];


        // Si tout est OK => auto_validated sinon needs_review

        $allOk = !in_array(false, $verification, true);

        $status = $allOk ? 'auto_validated' : 'needs_review';

        // Retourne JSON : status + résultats de vérification + texte OCR + chemins images
        
        return response()->json([
            'message'      => 'Inscription analysée',
            'status'       => $status,          // auto_validated ou needs_review
            'verification' => $verification,    // pour afficher OK / ❌
            'ocr' => [
                'bac' => $ocrBacText,
                'cin' => $ocrCinText,
            ],
            'paths' => [
                'bac' => $bacPath,
                'cin' => $cinPath,
            ],
        ], 201);
    }


    /**
     * Appelle i2OCR pour extraire le texte d'une image.
     */
private function performOcr(string $imagePath, string $language = 'eng'): string
{
    // Appelle l’API OCR.Space en multipart pour extraire le texte d’une image
    // (gère erreurs: pas de clé, HTTP error, API error, exception)
    $apiKey = env('OCR_SPACE_API_KEY');

    if (empty($apiKey)) {
        Log::error('OCR: pas de clé API dans .env');
        return '';
    }

    try {
        $response = Http::timeout(20)           
            ->asMultipart()
            ->attach('file', fopen($imagePath, 'r'), basename($imagePath))
            ->post('https://api.ocr.space/parse/image', [
                'apikey'   => $apiKey,
                'language' => $language,
            ]);

        if (!$response->ok()) {
            Log::error('OCR HTTP error: '.$response->status().' - '.$response->body());
            return '';
        }

        $json = $response->json();

        if (($json['IsErroredOnProcessing'] ?? false) === true) {
            Log::error('OCR API error: '.json_encode($json['ErrorMessage'] ?? []));
            return '';
        }

        $parsed = $json['ParsedResults'][0]['ParsedText'] ?? '';
        $parsed = trim($parsed);

        Log::info('OCR TEXT = '.$parsed);

        return $parsed;
    } catch (\Throwable $e) {
        Log::error('OCR exception: '.$e->getMessage());
        return '';
    }
}




    /**
     * Vérifie si $needle est contenu dans $haystack, sans sensibilité à la casse.
     * Fonctionne aussi avec UTF-8 (arabe).
     */
    private function containsIgnoreCase(string $haystack, string $needle): bool
    {
        // Vérifie si needle est contenu dans haystack (sans casse, UTF-8 ok)

        $haystackNorm = mb_strtolower($this->normalizeSpaces($haystack), 'UTF-8');
        $needleNorm   = mb_strtolower($this->normalizeSpaces($needle), 'UTF-8');

        if ($needleNorm === '') {
            return false;
        }

        return mb_strpos($haystackNorm, $needleNorm, 0, 'UTF-8') !== false;
    }

    /**
     * Normalise les espaces, supprime les espaces multiples.
     */
    private function normalizeSpaces(string $text): string
    {
        // Nettoie le texte : supprime espaces multiples + trim

        $text = preg_replace('/\s+/', ' ', $text);
        return trim($text);
    }


  /**
 * Similarité globale entre deux chaînes (0.0 à 1.0).
 */
private function similarityScore(string $a, string $b): float
{
    $a = $this->normalizeSpaces($a);
    $b = $this->normalizeSpaces($b);

    if ($a === '' || $b === '') {
        return 0.0;
    }

    similar_text($a, $b, $percent);
    return $percent / 100.0;
}

/**
 * Fuzzy match pour texte en arabe.
 */
private function fuzzyContains(string $haystack, string $needle, float $threshold = 0.5): bool
{
    // Fuzzy match (surtout pour arabe) : cherche une correspondance approximative
        // retourne true si score >= threshold
    $haystack = $this->normalizeSpaces($haystack);
    $needle   = $this->normalizeSpaces($needle);

    if ($needle === '' || $haystack === '') {
        return false;
    }

    // Match exact → OK
    if (mb_strpos($haystack, $needle, 0, 'UTF-8') !== false) {
        return true;
    }

    $lenNeedle = mb_strlen($needle, 'UTF-8');
    $lenHay    = mb_strlen($haystack, 'UTF-8');

    if ($lenHay <= $lenNeedle) {
        return $this->similarityScore($haystack, $needle) >= $threshold;
    }

    $best = 0.0;
    for ($i = 0; $i <= $lenHay - $lenNeedle; $i++) {
        $chunk = mb_substr($haystack, $i, $lenNeedle, 'UTF-8');
        $score = $this->similarityScore($chunk, $needle);
        if ($score > $best) {
            $best = $score;
        }
        if ($score >= $threshold) {
            return true;
        }
    }

    \Log::info("Fuzzy match '$needle' best score = $best");
    return false;
}

/**
 * Normalise alphanumérique pour code Massar.
 */
private function normalizeAlnum(string $s): string
{
        // Garde juste A-Z et 0-9 (utile pour Massar/CIN) + uppercase

    $s = strtoupper($s);
    $s = preg_replace('/[^A-Z0-9]+/', '', $s);
    return $s;
}

/**
 * Fuzzy match alphanum code Massar.: : cherche code approximatif dans l’OCR
 */
private function fuzzyAlnumContains(string $haystack, string $needle, float $threshold = 0.7): bool
{
    $h = $this->normalizeAlnum($haystack);
    $n = $this->normalizeAlnum($needle);

    if ($h === '' || $n === '') {
        return false;
    }

    if (strpos($h, $n) !== false) {
        return true;
    }

    $lenH = strlen($h);
    $lenN = strlen($n);

    if ($lenH <= $lenN) {
        return $this->similarityScore($h, $n) >= $threshold;
    }

    $best = 0.0;
    for ($i = 0; $i <= $lenH - $lenN; $i++) {
        $chunk = substr($h, $i, $lenN);
        similar_text($chunk, $n, $percent);
        $score = $percent / 100.0;
        if ($score > $best) {
            $best = $score;
        }
        if ($score >= $threshold) {
            return true;
        }
    }

    \Log::info("Fuzzy alnum '$needle' best score = $best");
    return false;
}

/**
 * Vérifie qu'une date (YYYY-MM-DD) apparaît dans le texte OCR,
 */
private function dateMatchesOcr(string $ocrText, string $isoDate): bool
{
    $digits = preg_replace('/\D+/', '', $ocrText);
    if ($digits === '') {
        return false;
    }

    try {
        $dt = new \DateTime($isoDate);
    } catch (\Exception $e) {
        return false;
    }

    $y = $dt->format('Y');
    $m = $dt->format('m');
    $d = $dt->format('d');
    $yy = substr($y, 2);

    $patterns = [
        $d.$m.$y,   // 07 11 2004
        $y.$m.$d,   // 2004 11 07
        $d.$m.$yy,  // 07 11 04
        $yy.$m.$d,  // 04 11 07
    ];

    foreach ($patterns as $p) {
        if (strpos($digits, $p) !== false) {
            return true;
        }
    }

    \Log::info("Date '$isoDate' not found in OCR digits '$digits'");
    return false;
}



}
