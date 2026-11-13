
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WordDb.instance.database;
  runApp(const JlptApp());
}

class JlptApp extends StatelessWidget {
  const JlptApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JLPT',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple,),
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFFAFAFA), elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    home: const MainShell(),
  );
}

class Word {
  final int id, intervalDays, correctCount, wrongCount;
  final String jp, reading, meaning, pos, example, exampleMeaning;
  final DateTime dueAt;
  Word(Map<String, Object?> m)
    : id=m['id'] as int, jp=m['jp'] as String, reading=m['reading'] as String,
      meaning=m['meaning'] as String, pos=m['pos'] as String,
      example=m['example'] as String, exampleMeaning=m['exampleMeaning'] as String,
      intervalDays=m['intervalDays'] as int, correctCount=m['correctCount'] as int,
      wrongCount=m['wrongCount'] as int, dueAt=DateTime.fromMillisecondsSinceEpoch(m['dueAt'] as int);
}

class WordDb {
  WordDb._();
  static final instance = WordDb._();
  Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    final base = await getDatabasesPath();
    _database = await openDatabase(p.join(base, 'jlpt_words.db'), version: 1, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE words(
          id INTEGER PRIMARY KEY AUTOINCREMENT, jp TEXT, reading TEXT, meaning TEXT,
          pos TEXT, example TEXT, exampleMeaning TEXT, intervalDays INTEGER DEFAULT 0,
          dueAt INTEGER, correctCount INTEGER DEFAULT 0, wrongCount INTEGER DEFAULT 0
        )
      ''');
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final item in sampleWords) {
        await db.insert('words', {...item, 'dueAt': now});
      }
    });
    return _database!;
  }

Future<void> _seedMissingWords(Database db) async {
  final rows = await db.query(
    'words',
    columns: ['jp', 'reading'],
  );

  final existing = rows
      .map((r) => '${r['jp']}|${r['reading']}')
      .toSet();

  final now = DateTime.now().millisecondsSinceEpoch;

  for (final item in sampleWords) {
    final key = '${item['jp']}|${item['reading']}';

    if (!existing.contains(key)) {
      await db.insert('words', {
        ...item,
        'dueAt': now,
      });
      existing.add(key);
    }
  }
}

  Future<List<Word>> all() async {
    final rows = await (await database).query('words', orderBy: 'jp');
    return rows.map(Word.new).toList();
  }

  Future<List<Word>> due() async {
    final rows = await (await database).query('words',
      where: 'dueAt <= ?', whereArgs: [DateTime.now().millisecondsSinceEpoch], orderBy: 'dueAt');
    return rows.map(Word.new).toList();
  }

  Future<void> answer(int id, bool correct) async {
    final db = await database;
    final rows = await db.query('words', where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final w = Word(rows.first);
    final interval = correct
      ? (w.intervalDays == 0 ? 1 : w.intervalDays < 3 ? 3 : w.intervalDays < 7 ? 7 : 14)
      : 0;
    final due = correct ? DateTime.now().add(Duration(days: interval))
                        : DateTime.now().add(const Duration(minutes: 10));
    await db.update('words', {
      'intervalDays': interval, 'dueAt': due.millisecondsSinceEpoch,
      'correctCount': w.correctCount + (correct ? 1 : 0),
      'wrongCount': w.wrongCount + (correct ? 0 : 1),
    }, where: 'id=?', whereArgs: [id]);
  }
}

final sampleWords = <Map<String, Object>>[
  {'jp':'準備','reading':'じゅんび','meaning':'준비','pos':'명사','example':'明日の準備をします。','exampleMeaning':'내일 준비를 합니다.'},
  {'jp':'経験','reading':'けいけん','meaning':'경험','pos':'명사','example':'日本へ行った経験があります。','exampleMeaning':'일본에 간 경험이 있습니다.'},
  {'jp':'約束','reading':'やくそく','meaning':'약속','pos':'명사','example':'友達と約束しました。','exampleMeaning':'친구와 약속했습니다.'},
  {'jp':'説明','reading':'せつめい','meaning':'설명','pos':'명사','example':'先生が説明しています。','exampleMeaning':'선생님이 설명하고 있습니다.'},
  {'jp':'連絡','reading':'れんらく','meaning':'연락','pos':'명사·する동사','example':'後で連絡します。','exampleMeaning':'나중에 연락하겠습니다.'},
  {'jp':'予定','reading':'よてい','meaning':'예정','pos':'명사','example':'週末は予定があります。','exampleMeaning':'주말에는 예정이 있습니다.'},
  {'jp':'途中','reading':'とちゅう','meaning':'도중','pos':'명사','example':'学校へ行く途中で会いました。','exampleMeaning':'학교에 가는 도중에 만났습니다.'},
  {'jp':'最近','reading':'さいきん','meaning':'최근','pos':'명사·부사','example':'最近忙しいです。','exampleMeaning':'최근 바쁩니다.'},
  {'jp':'選ぶ','reading':'えらぶ','meaning':'고르다','pos':'동사','example':'好きな色を選んでください。','exampleMeaning':'좋아하는 색을 골라 주세요.'},
  {'jp':'比べる','reading':'くらべる','meaning':'비교하다','pos':'동사','example':'二つの写真を比べます。','exampleMeaning':'두 사진을 비교합니다.'},
  {'jp':'続ける','reading':'つづける','meaning':'계속하다','pos':'동사','example':'毎日勉強を続けています。','exampleMeaning':'매일 공부를 계속하고 있습니다.'},
  {'jp':'間に合う','reading':'まにあう','meaning':'시간에 맞다','pos':'동사','example':'電車に間に合いました。','exampleMeaning':'전철 시간에 맞췄습니다.'},
  {'jp':'慣れる','reading':'なれる','meaning':'익숙해지다','pos':'동사','example':'新しい生活に慣れました。','exampleMeaning':'새로운 생활에 익숙해졌습니다.'},
  {'jp':'増える','reading':'ふえる','meaning':'늘다','pos':'동사','example':'最近、仕事が増えました。','exampleMeaning':'최근 일이 늘었습니다.'},
  {'jp':'減る','reading':'へる','meaning':'줄다','pos':'동사','example':'雨が少なくなって水が減りました。','exampleMeaning':'비가 적게 와서 물이 줄었습니다.'},
  {'jp':'珍しい','reading':'めずらしい','meaning':'드물다, 진귀하다','pos':'い형용사','example':'珍しい花を見ました。','exampleMeaning':'진귀한 꽃을 보았습니다.'},
  {'jp':'厳しい','reading':'きびしい','meaning':'엄격하다','pos':'い형용사','example':'父は厳しい人です。','exampleMeaning':'아버지는 엄격한 사람입니다.'},
  {'jp':'必要','reading':'ひつよう','meaning':'필요','pos':'な형용사·명사','example':'パスポートが必要です。','exampleMeaning':'여권이 필요합니다.'},
  {'jp':'十分','reading':'じゅうぶん','meaning':'충분함','pos':'な형용사·명사','example':'時間は十分あります。','exampleMeaning':'시간은 충분히 있습니다.'},
  {'jp':'残念','reading':'ざんねん','meaning':'유감, 아쉬움','pos':'な형용사','example':'試合に負けて残念です。','exampleMeaning':'경기에서 져서 아쉽습니다.'},
];

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}
class _MainShellState extends State<MainShell> {
  int index = 0;
  final labels = ['JLPT', '단어 학습', '단어 시험', '복습', '통계'];
  @override
  Widget build(BuildContext context) {
    final pages = [const Dashboard(), const StudyPage(), const QuizPage(), const ReviewPage(), const StatsPage()];
    return Scaffold(
      appBar: AppBar(title: Text(labels[index], style: const TextStyle(fontWeight: FontWeight.w700))),
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '홈'),
          NavigationDestination(icon: Icon(Icons.style_outlined), label: '학습'),
          NavigationDestination(icon: Icon(Icons.quiz_outlined), label: '시험'),
          NavigationDestination(icon: Icon(Icons.refresh), label: '복습'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: '통계'),
        ],
      ),
    );
  }
}

class Metric extends StatelessWidget {
  final String label, value, unit;
  const Metric(this.label, this.value, this.unit, {super.key});
  @override
  Widget build(BuildContext context) => Expanded(child: Card(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
    child: Column(children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      const SizedBox(height: 7),
      Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      Text(unit, style: const TextStyle(fontSize: 11, color: Colors.black45)),
    ]),
  )));
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Word>>(
    future: WordDb.instance.all(),
    builder: (context, s) {
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final words = s.data!;
      final due = words.where((w) => !w.dueAt.isAfter(DateTime.now())).length;
      final c = words.fold<int>(0, (a, w) => a + w.correctCount);
      final x = words.fold<int>(0, (a, w) => a + w.wrongCount);
      final rate = c + x == 0 ? 0 : (c / (c + x) * 100).round();
      return ListView(padding: const EdgeInsets.all(20), children: [
        const Text('오늘도 조금씩, 꾸준하게.', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        const Text('JLPT N4 단어를 차근차근 익혀 보세요.', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 20),
        Row(children: [Metric('전체 단어', '${words.length}', '개'), const SizedBox(width: 8),
          Metric('복습할 단어', '$due', '개'), const SizedBox(width: 8), Metric('정답률', '$rate', '%')]),
        const SizedBox(height: 18),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('오늘의 학습', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          const Text('단어를 익히고 양방향 시험으로 기억을 확인해 보세요.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StudyPage())),
            icon: const Icon(Icons.play_arrow), label: const Text('단어 학습 시작')),
        ]))),
        const SizedBox(height: 10),
        const Text('초기 버전에는 예시 단어 20개가 포함되어 있습니다.', style: TextStyle(color: Colors.black45, fontSize: 12)),
      ]);
    },
  );
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
  @override
  void initState() { super.initState(); tts.setLanguage('ja-JP'); tts.setSpeechRate(0.42); load(); }
  Future<void> load() async { final w = await WordDb.instance.all(); if (mounted) setState(() => words = w); }
  @override
  void dispose() { tts.stop(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) return const Center(child: CircularProgressIndicator());
    final w = words[index % words.length];
    return Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
        Text('단어 ${index + 1} / ${words.length}', style: const TextStyle(color: Colors.black54)),
        Text(w.pos, style: const TextStyle(color: Colors.black45)),
      ]),
      const SizedBox(height: 10),
      LinearProgressIndicator(value: (index + 1) / words.length, minHeight: 5, color: Colors.black87, backgroundColor: Colors.black12),
      const Spacer(),
      Card(child: SizedBox(width: double.infinity, child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 18),
        child: Column(children: [
          Text(w.jp, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(w.reading, style: const TextStyle(fontSize: 19, color: Colors.black54)),
          const SizedBox(height: 22),
          if (reveal) ...[
            Text(w.meaning, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 18),
            Text(w.example, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 6),
            Text(w.exampleMeaning, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
          ] else const Text('뜻을 떠올린 다음 확인해 보세요.', style: TextStyle(color: Colors.black45)),
        ]),
      ))),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: () => tts.speak(w.jp), icon: const Icon(Icons.volume_up_outlined), label: const Text('발음 듣기')),
      const Spacer(),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => setState(() => reveal = !reveal), child: Text(reveal ? '뜻 가리기' : '뜻 확인'))),
        const SizedBox(width: 10),
        Expanded(child: FilledButton(onPressed: () => setState(() { index = (index + 1) % words.length; reveal = false; }), child: const Text('다음 단어'))),
      ]),
    ]));
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
  String direction = 'jp', feedback = '';
  bool? correct;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async { final w = await WordDb.instance.all(); if (mounted) setState(() { words = w; next(); }); }
  void next() {
    if (words.isEmpty) return;
    final copy = [...words]..shuffle();
    current = copy.first; input.clear(); correct = null; feedback = '';
  }
  Future<void> check() async {
    if (current == null || correct != null) return;
    final expected = direction == 'jp' ? current!.meaning : current!.jp;
    final actual = input.text.trim().replaceAll(' ', '');
    final ok = actual == expected.replaceAll(' ', '');
    await WordDb.instance.answer(current!.id, ok);
    setState(() { correct = ok; feedback = ok ? '정답입니다!' : '정답: $expected'; });
  }
  @override
  void dispose() { input.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (current == null) return const Center(child: CircularProgressIndicator());
    final w = current!;
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('양방향 단어 시험', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'jp', label: Text('일본어 → 한국어')), ButtonSegment(value: 'kr', label: Text('한국어 → 일본어'))],
        selected: {direction},
        onSelectionChanged: (s) => setState(() { direction = s.first; next(); }),
      ),
      const SizedBox(height: 24),
      Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16), child: Center(child: Column(children: [
        Text(direction == 'jp' ? w.jp : w.meaning, textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
        if (direction == 'jp') ...[const SizedBox(height: 8), Text(w.reading, style: const TextStyle(fontSize: 18, color: Colors.black54))],
      ])))),
      const SizedBox(height: 18),
      TextField(controller: input, enabled: correct == null, decoration: InputDecoration(hintText: direction == 'jp' ? '한국어 뜻 입력' : '일본어 단어 입력')),
      const SizedBox(height: 14),
      if (correct == null) FilledButton(onPressed: check, child: const Text('정답 확인'))
      else ...[
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(
          color: correct! ? const Color(0xFFEAF4EC) : const Color(0xFFFFEEEE), borderRadius: BorderRadius.circular(14)),
          child: Text(feedback, style: TextStyle(fontWeight: FontWeight.w700, color: correct! ? Colors.green.shade800 : Colors.red.shade800))),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => setState(next), child: const Text('다음 문제')),
      ],
    ]);
  }
}

class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Word>>(
    future: WordDb.instance.due(),
    builder: (context, s) {
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final list = s.data!;
      if (list.isEmpty) return const Center(child: Text('지금 복습할 단어가 없습니다.\\n잘하고 있어요!', textAlign: TextAlign.center));
      return ListView(padding: const EdgeInsets.all(16), children: [
        Text('복습 예정 ${list.length}개', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
        for (final w in list) Card(child: ListTile(
          title: Text('${w.jp}  ${w.reading}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${w.meaning} · 오답 ${w.wrongCount}회'),
          trailing: IconButton(icon: const Icon(Icons.volume_up_outlined), onPressed: () {
            final t = FlutterTts(); t.setLanguage('ja-JP'); t.speak(w.jp);
          }),
        )),
      ]);
    },
  );
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Word>>(
    future: WordDb.instance.all(),
    builder: (context, s) {
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final words = s.data!;
      final c = words.fold<int>(0, (a, w) => a + w.correctCount);
      final x = words.fold<int>(0, (a, w) => a + w.wrongCount);
      final total = c + x, rate = total == 0 ? 0 : (c / total * 100).round();
      final mastered = words.where((w) => w.intervalDays >= 7).length;
      final wrongWords = words.where((w) => w.wrongCount > 0).toList()..sort((a,b) => b.wrongCount.compareTo(a.wrongCount));
      return ListView(padding: const EdgeInsets.all(20), children: [
        const Text('학습 통계', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Row(children: [Metric('누적 정답', '$c', '회'), const SizedBox(width: 8), Metric('누적 오답', '$x', '회')]),
        const SizedBox(height: 8),
        Row(children: [Metric('정답률', '$rate', '%'), const SizedBox(width: 8), Metric('장기 기억', '$mastered', '개')]),
        const SizedBox(height: 22),
        const Text('다시 확인할 단어', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        if (wrongWords.isEmpty) const Text('아직 오답 기록이 없습니다.', style: TextStyle(color: Colors.black54)),
        for (final w in wrongWords.take(10)) ListTile(
          contentPadding: EdgeInsets.zero, title: Text('${w.jp} (${w.reading})'),
          subtitle: Text(w.meaning), trailing: Text('${w.wrongCount}회 오답'),
        ),
      ]);
    },
  );
}
