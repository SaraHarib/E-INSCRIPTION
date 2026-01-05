import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;

    final docsDir = await getApplicationDocumentsDirectory();
    final path = p.join(docsDir.path, 'inscriptions.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE inscriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code_massar TEXT,
            nom_fr TEXT,
            nom_ar TEXT,
            prenom_fr TEXT,
            prenom_ar TEXT,
            date_naissance TEXT,
            date_bac TEXT,
            cin TEXT,
            ville_fr TEXT,
            ville_ar TEXT,
            created_at TEXT
          )
        ''');
      },
    );

    return _db!;
  }

  Future<int> insertInscription(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('inscriptions', data);
  }

  // récupérer la liste
  Future<List<Map<String, dynamic>>> getAllInscriptions() async {
    final db = await database;
    return db.query('inscriptions', orderBy: 'id DESC');
  }
}
