/// Fields contain escaped, safe HTML for Anki's HTML import mode.
class AnkiExportNote {
  const AnkiExportNote({
    required this.id,
    required this.isPhrase,
    required this.fields,
  }) : assert(
         fields.length == fieldNames.length,
         'All Anki fields must be supplied.',
       );

  static const List<String> fieldNames = <String>[
    'Expression',
    'Phonetic',
    'Meaning',
    'Context',
    'Translation',
    'Source',
    'Time',
    'Kind',
  ];
  final String id;
  final bool isPhrase;
  final List<String> fields;
}

enum AnkiExportFormat { apkg, tsv, csv }
