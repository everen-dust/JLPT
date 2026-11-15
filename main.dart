
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await WordDb.instance.database;

  // 앱 시작 시 원격 단어 목록 자동 확인
  try {
    await WordDb.instance.syncRemoteWords();
  } catch (_) {
    // 인터넷 연결이 없더라도 앱은 실행
  }

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
          seedColor: Colors.deepPurple,
        ),
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFAFAFA),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      home: const MainShell(),
    );
  }
}

class Word {
  final int id;
  final int intervalDays;
  final int correctCount;
  final int wrongCount;

  final String jp;
  final String reading;
  final String meaning;
  final String pos;
  final String example;
  final String exampleMeaning;

  final DateTime dueAt;

  Word(Map<String, Object?> m)
      : id = m['id'] as int,
        jp = m['jp'] as String,
        reading = m['reading'] as String,
        meaning = m['meaning'] as String,
        pos = m['pos'] as String,
        example = m['example'] as String,
        exampleMeaning = m['exampleMeaning'] as String,
        intervalDays = m['intervalDays'] as int,
        correctCount = m['correctCount'] as int,
        wrongCount = m['wrongCount'] as int,
        dueAt = DateTime.fromMillisecondsSinceEpoch(
          m['dueAt'] as int,
        );
}

class WordDb {
  WordDb._();

  static final instance = WordDb._();

  static const String wordsUrl =
      'https://raw.githubusercontent.com/everen-dust/JLPT/main/words.json';

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final base = await getDatabasesPath();

    _database = await openDatabase(
      p.join(base, 'jlpt_words.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE words(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            jp TEXT,
            reading TEXT,
            meaning TEXT,
            pos TEXT,
            example TEXT,
            exampleMeaning TEXT,
            intervalDays INTEGER DEFAULT 0,
            dueAt INTEGER,
            correctCount INTEGER DEFAULT 0,
            wrongCount INTEGER DEFAULT 0
          )
        ''');
      },
    );

    return _database!;
  }

  // GitHub 단어 목록 업데이트
  Future<int> syncRemoteWords() async {
    final response = await http
        .get(Uri.parse(wordsUrl))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('단어 목록을 가져오지 못했습니다.');
    }

    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes),
    );

    if (decoded is! List) {
      throw const FormatException(
        'words.json 형식이 올바르지 않습니다.',
      );
    }

    final db = await database;
    int inserted = 0;

    await db.transaction((txn) async {
      for (final entry in decoded) {
        if (entry is! Map) continue;

        final jp = (entry['jp'] ?? '').toString().trim();
        final reading =
            (entry['reading'] ?? '').toString().trim();
        final meaning =
            (entry['meaning'] ?? '').toString().trim();

        if (jp.isEmpty || reading.isEmpty || meaning.isEmpty) {
          continue;
        }

        final found = await txn.query(
          'words',
          columns: ['id'],
          where: 'jp = ? AND reading = ?',
          whereArgs: [jp, reading],
          limit: 1,
        );

        // 기존 단어와 학습 기록은 그대로 유지
        if (found.isNotEmpty) continue;

        await txn.insert('words', {
          'jp': jp,
          'reading': reading,
          'meaning': meaning,
          'pos': (entry['pos'] ?? '기타').toString(),
          'example': (entry['example'] ?? '').toString(),
          'exampleMeaning':
              (entry['exampleMeaning'] ?? '').toString(),
          'intervalDays': 0,
          'dueAt': DateTime.now().millisecondsSinceEpoch,
          'correctCount': 0,
          'wrongCount': 0,
        });

        inserted++;
      }
    });

    return inserted;
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

  Future<void> answer(int id, bool correct) async {
    final db = await database;

    final rows = await db.query(
      'words',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return;

    final word = Word(rows.first);

    final interval = correct
        ? (word.intervalDays == 0
            ? 1
            : word.intervalDays < 3
                ? 3
                : word.intervalDays < 7
                    ? 7
                    : 14)
        : 0;

    final due = correct
        ? DateTime.now().add(Duration(days: interval))
        : DateTime.now().add(
            const Duration(minutes: 10),
          );

    await db.update(
      'words',
      {
        'intervalDays': interval,
        'dueAt': due.millisecondsSinceEpoch,
        'correctCount':
            word.correctCount + (correct ? 1 : 0),
        'wrongCount':
            word.wrongCount + (correct ? 0 : 1),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;

  final labels = [
    'JLPT',
    '단어 학습',
    '단어 시험',
    '복습',
    '통계',
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      const Dashboard(),
      const StudyPage(),
      const QuizPage(),
      const ReviewPage(),
      const StatsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          labels[index],
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: pages[index],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          setState(() => index = value);
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
            icon: Icon(Icons.refresh),
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

class Metric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const Metric(
    this.label,
    this.value,
    this.unit, {
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 8,
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
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
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

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  bool updating = false;

  Future<void> updateWords() async {
    setState(() => updating = true);

    try {
      final count =
          await WordDb.instance.syncRemoteWords();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? '새로운 단어가 없습니다.'
                : '$count개의 단어를 추가했습니다.',
          ),
        ),
      );

      setState(() {});
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '업데이트에 실패했습니다. 인터넷을 확인해 주세요.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Word>>(
      future: WordDb.instance.all(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final words = snapshot.data!;

        final due = words
            .where(
              (word) =>
                  !word.dueAt.isAfter(DateTime.now()),
            )
            .length;

        final correct = words.fold<int>(
          0,
          (sum, word) => sum + word.correctCount,
        );

        final wrong = words.fold<int>(
          0,
          (sum, word) => sum + word.wrongCount,
        );

        final rate = correct + wrong == 0
            ? 0
            : (correct / (correct + wrong) * 100).round();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '오늘도 조금씩, 꾸준하게.',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'JLPT N4 단어를 차근차근 익혀 보세요.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Metric('전체 단어', '${words.length}', '개'),
                const SizedBox(width: 8),
                Metric('복습할 단어', '$due', '개'),
                const SizedBox(width: 8),
                Metric('정답률', '$rate', '%'),
              ],
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '오늘의 학습',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      '단어를 익히고 양방향 시험으로 기억을 확인해 보세요.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const StudyPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('단어 학습 시작'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: updating ? null : updateWords,
              icon: updating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.sync),
              label: Text(
                updating ? '업데이트 중...' : '단어 목록 업데이트',
              ),
            ),
          ],
        );
      },
    );
  }
}

class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  final tts = FlutterTts();

  List<Word> words = [];
  int index = 0;
  bool reveal = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    tts.setLanguage('ja-JP');
    tts.setSpeechRate(0.42);
    load();
  }

  Future<void> load() async {
    final result = await WordDb.instance.all();

    if (!mounted) return;

    setState(() {
      words = result;
      loading = false;
    });
  }

  @override
  void dispose() {
    tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (words.isEmpty) {
      return const Center(
        child: Text('등록된 단어가 없습니다. 홈에서 단어를 업데이트해 주세요.'),
      );
    }

    final word = words[index % words.length];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '단어 ${index + 1} / ${words.length}',
                style: const TextStyle(color: Colors.black54),
              ),
              Text(
                word.pos,
                style: const TextStyle(color: Colors.black45),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (index + 1) / words.length,
            minHeight: 5,
            color: Colors.black87,
            backgroundColor: Colors.black12,
          ),
          const Spacer(),
          Card(
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 40,
                  horizontal: 18,
                ),
                child: Column(
                  children: [
                    Text(
                      word.jp,
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      word.reading,
                      style: const TextStyle(
                        fontSize: 19,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (reveal) ...[
                      Text(
                        word.meaning,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        word.example,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 17),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        word.exampleMeaning,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black54,
                        ),
                      ),
                    ] else
                      const Text(
                        '뜻을 떠올린 다음 확인해 보세요.',
                        style: TextStyle(color: Colors.black45),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => tts.speak(word.jp),
            icon: const Icon(Icons.volume_up_outlined),
            label: const Text('발음 듣기'),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() => reveal = !reveal);
                  },
                  child: Text(reveal ? '뜻 가리기' : '뜻 확인'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
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
        ],
      ),
    );
  }
}

class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final input = TextEditingController();

  List<Word> words = [];
  Word? current;

  String direction = 'jp';
  String feedback = '';

  bool? correct;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final result = await WordDb.instance.all();

    if (!mounted) return;

    setState(() {
      words = result;
      loading = false;
      next();
    });
  }

  void next() {
    if (words.isEmpty) {
      current = null;
      return;
    }

    final copy = [...words]..shuffle();

    current = copy.first;
    input.clear();
    correct = null;
    feedback = '';
  }

  Future<void> check() async {
    if (current == null || correct != null) return;

    final expected =
        direction == 'jp' ? current!.meaning : current!.jp;

    final actual = input.text.trim().replaceAll(' ', '');

    final ok = actual == expected.replaceAll(' ', '');

    await WordDb.instance.answer(current!.id, ok);

    if (!mounted) return;

    setState(() {
      correct = ok;
      feedback = ok ? '정답입니다!' : '정답: $expected';
    });
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (words.is