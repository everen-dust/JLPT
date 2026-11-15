
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.instance.database;

  // 내장 단어를 먼저 등록하여 인터넷이 없어도 학습 가능
  await Db.instance.seedLocal();

  // 실행할 때 GitHub 단어 목록 확인
  try {
    await Db.instance.sync();
  } catch (_) {}

  runApp(const JlptApp());
}

class JlptApp extends StatelessWidget {
  const JlptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JLPT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6556A8),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F7FB),
      ),
      home: const Shell(),
    );
  }
}

class Word {
  final int id;
  final String jp;
  final String reading;
  final String meaning;
  final String pos;
  final String example;
  final String exampleMeaning;
  final int interval;
  final int correct;
  final int wrong;
  final DateTime dueAt;

  Word(Map<String, Object?> m)
      : id = m['id'] as int,
        jp = (m['jp'] ?? '') as String,
        reading = (m['reading'] ?? '') as String,
        meaning = (m['meaning'] ?? '') as String,
        pos = (m['pos'] ?? '기타') as String,
        example = (m['example'] ?? '') as String,
        exampleMeaning =
            (m['exampleMeaning'] ?? '') as String,
        interval = (m['intervalDays'] ?? 0) as int,
        correct = (m['correctCount'] ?? 0) as int,
        wrong = (m['wrongCount'] ?? 0) as int,
        dueAt = DateTime.fromMillisecondsSinceEpoch(
          (m['dueAt'] ?? 0) as int,
        );
}

class Db {
  Db._();

  static final instance = Db._();

  static const remote =
      'https://raw.githubusercontent.com/everen-dust/JLPT/main/words.json';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;

    final dir = await getDatabasesPath();

    _db = await openDatabase(
      p.join(dir, 'jlpt_words.db'),
      version: 1,
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE words(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            jp TEXT NOT NULL,
            reading TEXT NOT NULL,
            meaning TEXT NOT NULL,
            pos TEXT DEFAULT '기타',
            example TEXT DEFAULT '',
            exampleMeaning TEXT DEFAULT '',
            intervalDays INTEGER DEFAULT 0,
            dueAt INTEGER NOT NULL,
            correctCount INTEGER DEFAULT 0,
            wrongCount INTEGER DEFAULT 0,
            UNIQUE(jp, reading)
          )
        ''');
      },
    );

    return _db!;
  }

  Future<int> seedLocal() async {
    final raw = await rootBundle.loadString(
      'assets/words.json',
    );
    return importJson(raw);
  }

  Future<int> sync() async {
    final response = await http
        .get(Uri.parse(remote))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('단어 파일을 불러오지 못했습니다.');
    }

    return importJson(
      utf8.decode(response.bodyBytes),
    );
  }

  Future<int> importJson(String raw) async {
    final data = jsonDecode(raw);

    if (data is! List) {
      throw const FormatException('words.json 형식 오류');
    }

    final d = await database;
    int added = 0;

    await d.transaction((tx) async {
      for (final item in data) {
        if (item is! Map) continue;

        final jp = (item['jp'] ?? '').toString().trim();
        final reading =
            (item['reading'] ?? '').toString().trim();
        final meaning =
            (item['meaning'] ?? '').toString().trim();

        if (jp.isEmpty ||
            reading.isEmpty ||
            meaning.isEmpty) {
          continue;
        }

        final old = await tx.query(
          'words',
          columns: ['id'],
          where: 'jp = ? AND reading = ?',
          whereArgs: [jp, reading],
          limit: 1,
        );

        if (old.isNotEmpty) continue;

        await tx.insert(
          'words',
          {
            'jp': jp,
            'reading': reading,
            'meaning': meaning,
            'pos': (item['pos'] ?? '기타').toString(),
            'example': (item['example'] ?? '').toString(),
            'exampleMeaning':
                (item['exampleMeaning'] ?? '').toString(),
            'intervalDays': 0,
            'dueAt': DateTime.now().millisecondsSinceEpoch,
            'correctCount': 0,
            'wrongCount': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        added++;
      }
    });

    return added;
  }

  Future<List<Word>> all() async {
    final rows = await (await database).query(
      'words',
      orderBy: 'jp',
    );

    return rows.map(Word.new).toList();
  }

  Future<List<Word>> due() async {
    final rows = await (await database).query(
      'words',
      where: 'dueAt <= ?',
      whereArgs: [
        DateTime.now().millisecondsSinceEpoch,
      ],
      orderBy: 'dueAt',
    );

    return rows.map(Word.new).toList();
  }

  Future<void> answer(Word w, bool ok) async {
    final days = ok
        ? (w.interval == 0
            ? 1
            : w.interval < 3
                ? 3
                : w.interval < 7
                    ? 7
                    : 14)
        : 0;

    final due = ok
        ? DateTime.now().add(Duration(days: days))
        : DateTime.now().add(
            const Duration(minutes: 10),
          );

    await (await database).update(
      'words',
      {
        'intervalDays': days,
        'dueAt': due.millisecondsSinceEpoch,
        'correctCount': w.correct + (ok ? 1 : 0),
        'wrongCount': w.wrong + (ok ? 0 : 1),
      },
      where: 'id = ?',
      whereArgs: [w.id],
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;

  final pages = const [
    Home(),
    Learn(),
    Quiz(),
    Review(),
    Stats(),
  ];

  final titles = const [
    'JLPT',
    '단어 학습',
    '단어 시험',
    '복습',
    '통계',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[tab],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) {
          setState(() => tab = v);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            label: '학습',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            label: '시험',
          ),
          NavigationDestination(
            icon: Icon(Icons.replay_outlined),
            label: '복습',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            label: '통계',
          ),
        ],
      ),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool busy = false;

  Future<void> update() async {
    setState(() => busy = true);

    try {
      final n = await Db.instance.sync();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? '새 단어가 없습니다.'
                : '$n개 단어를 추가했습니다.',
          ),
        ),
      );

      setState(() {});
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('업데이트 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Word>>(
      future: Db.instance.all(),
      builder: (context, s) {
        if (!s.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final words = s.data!;

        final c = words.fold<int>(
          0,
          (a, w) => a + w.correct,
        );

        final x = words.fold<int>(
          0,
          (a, w) => a + w.wrong,
        );

        final rate =
            c + x == 0 ? 0 : (100 * c / (c + x)).round();

        final due = words
            .where(
              (w) => !w.dueAt.isAfter(DateTime.now()),
            )
            .length;

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              '매일 조금씩, 확실하게.',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'JLPT N4 어휘를 차근차근 익혀 보세요.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _Metric('전체 단어', '${words.length}', '개'),
                _Metric('복습 예정', '$due', '개'),
                _Metric('정답률', '$rate', '%'),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '단어 목록 업데이트',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '앱 실행 시 GitHub에서 새 단어를 확인합니다. '
                      '아래 버튼으로 직접 업데이트할 수도 있습니다.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: busy ? null : update,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync),
                        label: Text(
                          busy ? '확인 중...' : '수동 업데이트',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.menu_book),
                title: const Text('저장된 단어'),
                subtitle: Text('${words.length}개'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.replay),
                title: const Text('복습할 단어'),
                subtitle: Text('$due개'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _Metric(this.label, this.value, this.unit);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 4,
          ),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Voice {
  static final tts = FlutterTts();

  static Future<void> say(String text) async {
    await tts.setLanguage('ja-JP');
    await tts.setSpeechRate(0.45);
    await tts.speak(text);
  }
}

class Learn extends StatefulWidget {
  const Learn({super.key});

  @override
  State<Learn> createState() => _LearnState();
}

class _LearnState extends State<Learn> {
  late Future<List<Word>> future;
  int index = 0;
  bool reveal = false;

  @override
  void initState() {
    super.initState();
    future = Db.instance.all();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Word>>(
      future: future,
      builder: (context, s) {
        if (!s.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final words = s.data!;

        if (words.isEmpty) return const _Empty();

        final w = words[index % words.length];

        return Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Text('단어 ${index + 1} / ${words.length}'),
              Expanded(
                child: Center(
                  child: Card(
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              w.jp,
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              w.reading,
                              style: const TextStyle(
                                fontSize: 20,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 22),
                            if (reveal) ...[
                              Text(
                                w.meaning,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                w.pos,
                                style: const TextStyle(
                                  color: Colors.black54,
                                ),
                              ),
                              if (w.example.isNotEmpty) ...[
                                const Divider(height: 28),
                                Text(w.example),
                                Text(w.exampleMeaning),
                              ],
                            ] else
                              const Text(
                                '뜻을 떠올린 뒤 확인해 보세요.',
                              ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                IconButton.filledTonal(
                                  onPressed: () => Voice.say(w.jp),
                                  icon: const Icon(
                                    Icons.volume_up,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton(
                                  onPressed: () {
                                    setState(() {
                                      reveal = !reveal;
                                    });
                                  },
                                  child: Text(
                                    reveal ? '뜻 숨기기' : '뜻 확인',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      index = (index + 1) % words.length;
                      reveal = false;
                    });
                  },
                  child: const Text('다음 단어'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class Quiz extends StatefulWidget {
  const Quiz({super.key});

  @override
  State<Quiz> createState() => _QuizState();
}

class _QuizState extends State<Quiz> {
  List<Word> words = [];
  List<String> choices = [];

  int at = 0;
  int? selected;

  bool answered = false;
  bool loading = true;
  bool reverse = false;

  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    setState(() {
      loading = true;
      at = 0;
      selected = null;
      answered = false;
    });

    words = await Db.instance.all();
    words.shuffle();

    if (!mounted) return;

    setState(() {
      loading = false;
      prepare();
    });
  }

  void prepare() {
    if (words.isEmpty) {
      choices = [];
      return;
    }

    reverse = at.isOdd;

    final w = words[at];
    final answer = reverse ? w.jp : w.meaning;

    final others = words
        .where((x) => x.id != w.id)
        .map((x) => reverse ? x.jp : x.meaning)
        .toSet()
        .toList()
      ..shuffle();

    choices = ([answer, ...others.take(3)]..shuffle());
  }

  Future<void> choose(int i) async {
    if (answered) return;

    final w = words[at];

    final ok = choices[i] ==
        (reverse ? w.jp : w.meaning);

    setState(() {
      selected = i;
      answered = true;
    });

    await Db.instance.answer(w, ok);
  }

  void next() {
    if (at + 1 >= words.length) {
      start();
      return;
    }

    setState(() {
      at++;
      selected = null;
      answered = false;
      prepare();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (words.isEmpty) return const _Empty();

    final w = words[at];
    final answer = reverse ? w.jp : w.meaning;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('문제 ${at + 1} / ${words.length}'),
        Card(
 