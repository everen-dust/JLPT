
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

    await _seedMissingWords(_database!);

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

{'jp':'安心','reading':'あんしん','meaning':'안심','pos':'명사·な형용사','example':'ここにいると安心します。','exampleMeaning':'여기에 있으면 안심됩니다.'},
{'jp':'安全','reading':'あんぜん','meaning':'안전','pos':'명사·な형용사','example':'安全な場所で待ちます。','exampleMeaning':'안전한 장소에서 기다립니다.'},
{'jp':'案内','reading':'あんない','meaning':'안내','pos':'명사·する동사','example':'駅まで案内します。','exampleMeaning':'역까지 안내합니다.'},
{'jp':'意見','reading':'いけん','meaning':'의견','pos':'명사','example':'あなたの意見を聞きたいです。','exampleMeaning':'당신의 의견을 듣고 싶습니다.'},
{'jp':'以上','reading':'いじょう','meaning':'이상','pos':'명사·부사','example':'以上で説明を終わります。','exampleMeaning':'이상으로 설명을 마칩니다.'},
{'jp':'以下','reading':'いか','meaning':'이하','pos':'명사','example':'十人以下でお願いします。','exampleMeaning':'10명 이하로 부탁합니다.'},
{'jp':'以外','reading':'いがい','meaning':'이외','pos':'명사','example':'日曜日以外は働きます。','exampleMeaning':'일요일 이외에는 일합니다.'},
{'jp':'以内','reading':'いない','meaning':'이내','pos':'명사','example':'三日以内に返事します。','exampleMeaning':'3일 이내에 답하겠습니다.'},
{'jp':'一度','reading':'いちど','meaning':'한 번','pos':'부사','example':'一度日本へ行きたいです。','exampleMeaning':'한 번 일본에 가고 싶습니다.'},
{'jp':'運転','reading':'うんてん','meaning':'운전','pos':'명사·する동사','example':'父は車を運転します。','exampleMeaning':'아버지는 차를 운전합니다.'},
{'jp':'運動','reading':'うんどう','meaning':'운동','pos':'명사·する동사','example':'毎朝運動しています。','exampleMeaning':'매일 아침 운동하고 있습니다.'},
{'jp':'お祝い','reading':'おいわい','meaning':'축하','pos':'명사','example':'誕生日のお祝いをしました。','exampleMeaning':'생일 축하를 했습니다.'},
{'jp':'お見舞い','reading':'おみまい','meaning':'병문안','pos':'명사','example':'友達のお見舞いに行きます。','exampleMeaning':'친구의 병문안을 갑니다.'},
{'jp':'おかげ','reading':'おかげ','meaning':'덕분','pos':'명사','example':'先生のおかげで合格しました。','exampleMeaning':'선생님 덕분에 합격했습니다.'},
{'jp':'お宅','reading':'おたく','meaning':'댁','pos':'명사','example':'お宅に電話しました。','exampleMeaning':'댁에 전화했습니다.'},
{'jp':'お釣り','reading':'おつり','meaning':'거스름돈','pos':'명사','example':'お釣りを受け取りました。','exampleMeaning':'거스름돈을 받았습니다.'},
{'jp':'お礼','reading':'おれい','meaning':'감사 인사','pos':'명사','example':'先生にお礼を言いました。','exampleMeaning':'선생님께 감사 인사를 했습니다.'},
{'jp':'片付ける','reading':'かたづける','meaning':'정리하다','pos':'동사','example':'部屋を片付けます。','exampleMeaning':'방을 정리합니다.'},
{'jp':'間違える','reading':'まちがえる','meaning':'틀리다','pos':'동사','example':'答えを間違えました。','exampleMeaning':'답을 틀렸습니다.'},
{'jp':'見つける','reading':'みつける','meaning':'찾아내다','pos':'동사','example':'駅の近くで店を見つけました。','exampleMeaning':'역 근처에서 가게를 찾았습니다.'},
{'jp':'見つかる','reading':'みつかる','meaning':'발견되다','pos':'동사','example':'鍵が見つかりました。','exampleMeaning':'열쇠를 찾았습니다.'},
{'jp':'申し込む','reading':'もうしこむ','meaning':'신청하다','pos':'동사','example':'試験に申し込みました。','exampleMeaning':'시험에 신청했습니다.'},
{'jp':'迎える','reading':'むかえる','meaning':'마중하다·맞이하다','pos':'동사','example':'駅で友達を迎えます。','exampleMeaning':'역에서 친구를 마중합니다.'},
{'jp':'戻る','reading':'もどる','meaning':'돌아가다','pos':'동사','example':'家に戻ります。','exampleMeaning':'집으로 돌아갑니다.'},
{'jp':'役に立つ','reading':'やくにたつ','meaning':'도움이 되다','pos':'표현','example':'この本は役に立ちます。','exampleMeaning':'이 책은 도움이 됩니다.'},
{'jp':'用意','reading':'ようい','meaning':'준비','pos':'명사·する동사','example':'昼ご飯を用意します。','exampleMeaning':'점심을 준비합니다.'},
{'jp':'留守','reading':'るす','meaning':'부재중','pos':'명사','example':'家は留守でした。','exampleMeaning':'집은 비어 있었습니다.'},
{'jp':'連れて行く','reading':'つれていく','meaning':'데리고 가다','pos':'동사','example':'弟を学校へ連れて行きます。','exampleMeaning':'남동생을 학교에 데려갑니다.'},
{'jp':'届ける','reading':'とどける','meaning':'배달하다·전달하다','pos':'동사','example':'荷物を家に届けます。','exampleMeaning':'짐을 집으로 배달합니다.'},
{'jp':'比べる','reading':'くらべる','meaning':'비교하다','pos':'동사','example':'二つの値段を比べます。','exampleMeaning':'두 가격을 비교합니다。'},
  {'jp':'受付','reading':'うけつけ','meaning':'접수','pos':'명사','example':'受付で名前を書きます。','exampleMeaning':'접수처에서 이름을 씁니다.'},
  {'jp':'売り場','reading':'うりば','meaning':'판매장, 매장','pos':'명사','example':'靴売り場はどこですか。','exampleMeaning':'신발 매장은 어디인가요?'},
  {'jp':'売れる','reading':'うれる','meaning':'팔리다','pos':'동사','example':'この本はよく売れます。','exampleMeaning':'이 책은 잘 팔립니다.'},
  {'jp':'選ぶ','reading':'えらぶ','meaning':'고르다','pos':'동사','example':'好きな色を選んでください。','exampleMeaning':'좋아하는 색을 골라 주세요.'},
  {'jp':'遅れる','reading':'おくれる','meaning':'늦다, 지각하다','pos':'동사','example':'電車が遅れています。','exampleMeaning':'전철이 늦어지고 있습니다.'},
  {'jp':'起こす','reading':'おこす','meaning':'깨우다, 일으키다','pos':'동사','example':'明日六時に起こしてください。','exampleMeaning':'내일 6시에 깨워 주세요.'},
  {'jp':'行う','reading':'おこなう','meaning':'행하다, 실시하다','pos':'동사','example':'学校で試験を行います。','exampleMeaning':'학교에서 시험을 실시합니다.'},
  {'jp':'落とす','reading':'おとす','meaning':'떨어뜨리다','pos':'동사','example':'財布を落としました。','exampleMeaning':'지갑을 떨어뜨렸습니다.'},
  {'jp':'踊る','reading':'おどる','meaning':'춤추다','pos':'동사','example':'友達と踊りました。','exampleMeaning':'친구와 춤췄습니다.'},
  {'jp':'思い出す','reading':'おもいだす','meaning':'생각해 내다','pos':'동사','example':'昔のことを思い出しました。','exampleMeaning':'옛날 일을 생각해 냈습니다.'},
  {'jp':'思う','reading':'おもう','meaning':'생각하다','pos':'동사','example':'それはいいと思います。','exampleMeaning':'그것은 좋다고 생각합니다.'},
  {'jp':'折る','reading':'おる','meaning':'접다, 꺾다','pos':'동사','example':'紙を半分に折ります。','exampleMeaning':'종이를 반으로 접습니다.'},
  {'jp':'折れる','reading':'おれる','meaning':'접히다, 부러지다','pos':'동사','example':'鉛筆が折れました。','exampleMeaning':'연필이 부러졌습니다.'},
  {'jp':'変える','reading':'かえる','meaning':'바꾸다','pos':'동사','example':'予定を変えました。','exampleMeaning':'예정을 바꿨습니다.'},
  {'jp':'帰り','reading':'かえり','meaning':'돌아가는 길','pos':'명사','example':'帰りに本屋へ行きます。','exampleMeaning':'돌아가는 길에 서점에 갑니다.'},
  {'jp':'変わる','reading':'かわる','meaning':'변하다','pos':'동사','example':'天気が変わりました。','exampleMeaning':'날씨가 변했습니다.'},
  {'jp':'考える','reading':'かんがえる','meaning':'생각하다, 고려하다','pos':'동사','example':'将来について考えます。','exampleMeaning':'장래에 대해 생각합니다.'},
  {'jp':'聞こえる','reading':'きこえる','meaning':'들리다','pos':'동사','example':'外から音が聞こえます。','exampleMeaning':'밖에서 소리가 들립니다.'},
  {'jp':'決まる','reading':'きまる','meaning':'정해지다','pos':'동사','example':'旅行の日が決まりました。','exampleMeaning':'여행 날짜가 정해졌습니다.'},
  {'jp':'決める','reading':'きめる','meaning':'정하다','pos':'동사','example':'自分で決めてください。','exampleMeaning':'스스로 정해 주세요.'},
  {'jp':'比べる','reading':'くらべる','meaning':'비교하다','pos':'동사','example':'二つの商品を比べます。','exampleMeaning':'두 상품을 비교합니다.'},
  {'jp':'暮れる','reading':'くれる','meaning':'해가 지다','pos':'동사','example':'日が暮れてきました。','exampleMeaning':'해가 지기 시작했습니다.'},
  {'jp':'壊す','reading':'こわす','meaning':'망가뜨리다','pos':'동사','example':'時計を壊しました。','exampleMeaning':'시계를 망가뜨렸습니다.'},
  {'jp':'壊れる','reading':'こわれる','meaning':'고장 나다','pos':'동사','example':'パソコンが壊れました。','exampleMeaning':'컴퓨터가 고장 났습니다.'},
  {'jp':'探す','reading':'さがす','meaning':'찾다','pos':'동사','example':'駅の近くで店を探します。','exampleMeaning':'역 근처에서 가게를 찾습니다.'},
  {'jp':'下がる','reading':'さがる','meaning':'내려가다','pos':'동사','example':'気温が下がりました。','exampleMeaning':'기온이 내려갔습니다.'},
  {'jp':'下げる','reading':'さげる','meaning':'내리다','pos':'동사','example':'音を少し下げてください。','exampleMeaning':'소리를 조금 낮춰 주세요.'},
  {'jp':'差し上げる','reading':'さしあげる','meaning':'드리다','pos':'동사','example':'先生に花を差し上げました。','exampleMeaning':'선생님께 꽃을 드렸습니다.'},
  {'jp':'騒ぐ','reading':'さわぐ','meaning':'떠들다','pos':'동사','example':'図書館で騒がないでください。','exampleMeaning':'도서관에서 떠들지 마세요.'},
  {'jp':'叱る','reading':'しかる','meaning':'꾸짖다','pos':'동사','example':'父に叱られました。','exampleMeaning':'아버지께 꾸중을 들었습니다.'},
  {'jp':'知らせる','reading':'しらせる','meaning':'알리다','pos':'동사','example':'結果をすぐ知らせます。','exampleMeaning':'결과를 바로 알리겠습니다.'},
  {'jp':'調べる','reading':'しらべる','meaning':'조사하다, 알아보다','pos':'동사','example':'辞書で意味を調べます。','exampleMeaning':'사전에서 의미를 찾아봅니다.'},
  {'jp':'進む','reading':'すすむ','meaning':'나아가다, 진행되다','pos':'동사','example':'計画が順調に進んでいます。','exampleMeaning':'계획이 순조롭게 진행되고 있습니다.'},
  {'jp':'進める','reading':'すすめる','meaning':'진행하다','pos':'동사','example':'仕事を進めてください。','exampleMeaning':'일을 진행해 주세요.'},
  {'jp':'捨てる','reading':'すてる','meaning':'버리다','pos':'동사','example':'ごみを捨てます。','exampleMeaning':'쓰레기를 버립니다.'},
  {'jp':'育つ','reading':'そだつ','meaning':'자라다, 성장하다','pos':'동사','example':'子供は元気に育っています。','exampleMeaning':'아이는 건강하게 자라고 있습니다.'},
  {'jp':'育てる','reading':'そだてる','meaning':'기르다, 키우다','pos':'동사','example':'花を育てています。','exampleMeaning':'꽃을 기르고 있습니다.'},
  {'jp':'倒れる','reading':'たおれる','meaning':'쓰러지다','pos':'동사','example':'強い風で木が倒れました。','exampleMeaning':'강한 바람에 나무가 쓰러졌습니다.'},
  {'jp':'足りる','reading':'たりる','meaning':'충분하다','pos':'동사','example':'時間が足りません。','exampleMeaning':'시간이 부족합니다.'},
  {'jp':'捕まえる','reading':'つかまえる','meaning':'붙잡다','pos':'동사','example':'警察が犯人を捕まえました。','exampleMeaning':'경찰이 범인을 붙잡았습니다.'},
  {'jp':'続く','reading':'つづく','meaning':'계속되다','pos':'동사','example':'雨が三日間続きました。','exampleMeaning':'비가 3일 동안 계속되었습니다.'},
  {'jp':'続ける','reading':'つづける','meaning':'계속하다','pos':'동사','example':'毎日勉強を続けます。','exampleMeaning':'매일 공부를 계속합니다.'},
  {'jp':'伝える','reading':'つたえる','meaning':'전하다','pos':'동사','example':'母に電話で伝えました。','exampleMeaning':'어머니께 전화로 전했습니다.'},
  {'jp':'手伝う','reading':'てつだう','meaning':'돕다','pos':'동사','example':'母の料理を手伝います。','exampleMeaning':'어머니의 요리를 돕습니다.'},
  {'jp':'届ける','reading':'とどける','meaning':'배달하다, 전달하다','pos':'동사','example':'荷物を家に届けます。','exampleMeaning':'짐을 집으로 배달합니다.'},
  {'jp':'直す','reading':'なおす','meaning':'고치다, 수리하다','pos':'동사','example':'間違いを直してください。','exampleMeaning':'틀린 부분을 고쳐 주세요.'},
  {'jp':'直る','reading':'なおる','meaning':'고쳐지다','pos':'동사','example':'時計が直りました。','exampleMeaning':'시계가 고쳐졌습니다.'},
  {'jp':'泣く','reading':'なく','meaning':'울다','pos':'동사','example':'赤ちゃんが泣いています。','exampleMeaning':'아기가 울고 있습니다.'},
  {'jp':'亡くなる','reading':'なくなる','meaning':'돌아가시다','pos':'동사','example':'祖父は去年亡くなりました。','exampleMeaning':'할아버지는 작년에 돌아가셨습니다.'},
  {'jp':'投げる','reading':'なげる','meaning':'던지다','pos':'동사','example':'ボールを遠くに投げます。','exampleMeaning':'공을 멀리 던집니다.'},
  {'jp':'慣れる','reading':'なれる','meaning':'익숙해지다','pos':'동사','example':'新しい生活に慣れました。','exampleMeaning':'새로운 생활에 익숙해졌습니다.'},
  {'jp':'似る','reading':'にる','meaning':'닮다','pos':'동사','example':'兄は父に似ています。','exampleMeaning':'형은 아버지를 닮았습니다.'},
  {'jp':'盗む','reading':'ぬすむ','meaning':'훔치다','pos':'동사','example':'人の物を盗んではいけません。','exampleMeaning':'남의 물건을 훔쳐서는 안 됩니다.'},
  {'jp':'濡れる','reading':'ぬれる','meaning':'젖다','pos':'동사','example':'雨で服が濡れました。','exampleMeaning':'비에 옷이 젖었습니다.'},
  {'jp':'眠る','reading':'ねむる','meaning':'잠자다','pos':'동사','example':'赤ちゃんはよく眠っています。','exampleMeaning':'아기는 잘 자고 있습니다.'},
  {'jp':'残る','reading':'のこる','meaning':'남다','pos':'동사','example':'料理が少し残りました。','exampleMeaning':'요리가 조금 남았습니다.'},
  {'jp':'運ぶ','reading':'はこぶ','meaning':'운반하다','pos':'동사','example':'荷物を部屋に運びます。','exampleMeaning':'짐을 방으로 옮깁니다.'},
  {'jp':'始める','reading':'はじめる','meaning':'시작하다','pos':'동사','example':'新しい仕事を始めます。','exampleMeaning':'새로운 일을 시작합니다.'},
  {'jp':'冷える','reading':'ひえる','meaning':'차가워지다','pos':'동사','example':'夜は体が冷えます。','exampleMeaning':'밤에는 몸이 차가워집니다.'},
  {'jp':'冷やす','reading':'ひやす','meaning':'차게 하다','pos':'동사','example':'水を冷やしてください。','exampleMeaning':'물을 차게 해 주세요.'},
  {'jp':'拾う','reading':'ひろう','meaning':'줍다','pos':'동사','example':'道で財布を拾いました。','exampleMeaning':'길에서 지갑을 주웠습니다.'},
  {'jp':'増える','reading':'ふえる','meaning':'늘어나다','pos':'동사','example':'外国人の観光客が増えています。','exampleMeaning':'외국인 관광객이 늘고 있습니다.'},
  {'jp':'増やす','reading':'ふやす','meaning':'늘리다','pos':'동사','example':'野菜を食べる量を増やします。','exampleMeaning':'채소를 먹는 양을 늘립니다.'},
  {'jp':'踏む','reading':'ふむ','meaning':'밟다','pos':'동사','example':'足を踏まれました。','exampleMeaning':'발을 밟혔습니다.'},
  {'jp':'褒める','reading':'ほめる','meaning':'칭찬하다','pos':'동사','example':'先生が私を褒めました。','exampleMeaning':'선생님이 저를 칭찬했습니다.'},
  {'jp':'間に合う','reading':'まにあう','meaning':'시간에 맞다','pos':'동사','example':'電車に間に合いました。','exampleMeaning':'전철 시간에 맞췄습니다.'},
  {'jp':'間違う','reading':'まちがう','meaning':'잘못되다, 틀리다','pos':'동사','example':'答えが間違っています。','exampleMeaning':'답이 틀렸습니다.'},
  {'jp':'見える','reading':'みえる','meaning':'보이다','pos':'동사','example':'窓から海が見えます。','exampleMeaning':'창문에서 바다가 보입니다.'},
  {'jp':'向かう','reading':'むかう','meaning':'향하다','pos':'동사','example':'駅に向かっています。','exampleMeaning':'역으로 향하고 있습니다.'},
  {'jp':'迎える','reading':'むかえる','meaning':'맞이하다','pos':'동사','example':'駅で友達を迎えます。','exampleMeaning':'역에서 친구를 맞이합니다.'},
  {'jp':'申し込む','reading':'もうしこむ','meaning':'신청하다','pos':'동사','example':'旅行に申し込みました。','exampleMeaning':'여행을 신청했습니다.'},
  {'jp':'戻る','reading':'もどる','meaning':'돌아가다','pos':'동사','example':'家に戻ります。','exampleMeaning':'집으로 돌아갑니다.'},
  {'jp':'戻す','reading':'もどす','meaning':'되돌리다','pos':'동사','example':'本を棚に戻します。','exampleMeaning':'책을 책장에 되돌려 놓습니다.'},
  {'jp':'焼く','reading':'やく','meaning':'굽다','pos':'동사','example':'魚を焼きます。','exampleMeaning':'생선을 굽습니다.'},
  {'jp':'焼ける','reading':'やける','meaning':'구워지다','pos':'동사','example':'パンがよく焼けました。','exampleMeaning':'빵이 잘 구워졌습니다.'},
  {'jp':'役に立つ','reading':'やくにたつ','meaning':'도움이 되다','pos':'동사','example':'この本は役に立ちます。','exampleMeaning':'이 책은 도움이 됩니다.'},
  {'jp':'止む','reading':'やむ','meaning':'그치다','pos':'동사','example':'雨が止みました。','exampleMeaning':'비가 그쳤습니다.'},
  {'jp':'許す','reading':'ゆるす','meaning':'용서하다, 허락하다','pos':'동사','example':'友達を許しました。','exampleMeaning':'친구를 용서했습니다.'},
  {'jp':'喜ぶ','reading':'よろこぶ','meaning':'기뻐하다','pos':'동사','example':'母がとても喜びました。','exampleMeaning':'어머니가 매우 기뻐하셨습니다.'},
  {'jp':'沸かす','reading':'わかす','meaning':'끓이다','pos':'동사','example':'お湯を沸かします。','exampleMeaning':'물을 끓입니다.'},
  {'jp':'沸く','reading':'わく','meaning':'끓다','pos':'동사','example':'お湯が沸きました。','exampleMeaning':'물이 끓었습니다.'},
  {'jp':'別れる','reading':'わかれる','meaning':'헤어지다','pos':'동사','example':'駅で友達と別れました。','exampleMeaning':'역에서 친구와 헤어졌습니다.'},
  {'jp':'笑う','reading':'わらう','meaning':'웃다','pos':'동사','example':'みんなで笑いました。','exampleMeaning':'모두 함께 웃었습니다.'},
  {'jp':'割合','reading':'わりあい','meaning':'비율, 비교적','pos':'명사','example':'学生の割合が高いです。','exampleMeaning':'학생의 비율이 높습니다.'},
  {'jp':'場合','reading':'ばあい','meaning':'경우','pos':'명사','example':'雨の場合は中止です。','exampleMeaning':'비가 오는 경우에는 취소입니다.'},
  {'jp':'場所','reading':'ばしょ','meaning':'장소','pos':'명사','example':'静かな場所で勉強します。','exampleMeaning':'조용한 장소에서 공부합니다.'},
  {'jp':'番組','reading':'ばんぐみ','meaning':'방송 프로그램','pos':'명사','example':'好きな番組を見ます。','exampleMeaning':'좋아하는 프로그램을 봅니다.'},
  {'jp':'文化','reading':'ぶんか','meaning':'문화','pos':'명사','example':'日本の文化を勉強します。','exampleMeaning':'일본 문화를 공부합니다.'},
  {'jp':'文学','reading':'ぶんがく','meaning':'문학','pos':'명사','example':'日本文学に興味があります。','exampleMeaning':'일본 문학에 관심이 있습니다.'},
  {'jp':'貿易','reading':'ぼうえき','meaning':'무역','pos':'명사','example':'この国は貿易が盛んです。','exampleMeaning':'이 나라는 무역이 활발합니다.'},
  {'jp':'法律','reading':'ほうりつ','meaning':'법률','pos':'명사','example':'法律を守りましょう。','exampleMeaning':'법률을 지킵시다.'},
  {'jp':'方法','reading':'ほうほう','meaning':'방법','pos':'명사','example':'いい方法を考えます。','exampleMeaning':'좋은 방법을 생각합니다.'},
  {'jp':'星','reading':'ほし','meaning':'별','pos':'명사','example':'夜に星を見ました。','exampleMeaning':'밤에 별을 보았습니다.'},
  {'jp':'真ん中','reading':'まんなか','meaning':'한가운데','pos':'명사','example':'部屋の真ん中に机があります。','exampleMeaning':'방 한가운데에 책상이 있습니다.'},
  {'jp':'周り','reading':'まわり','meaning':'주변','pos':'명사','example':'学校の周りに店があります。','exampleMeaning':'학교 주변에 가게가 있습니다.'},
  {'jp':'港','reading':'みなと','meaning':'항구','pos':'명사','example':'港に船が止まっています。','exampleMeaning':'항구에 배가 정박해 있습니다.'},
  {'jp':'昔','reading':'むかし','meaning':'옛날','pos':'명사','example':'昔ここに住んでいました。','exampleMeaning':'옛날에 이곳에 살았습니다.'},
  {'jp':'無理','reading':'むり','meaning':'무리, 불가능','pos':'명사','example':'無理をしないでください。','exampleMeaning':'무리하지 마세요.'},
  {'jp':'約束','reading':'やくそく','meaning':'약속','pos':'명사','example':'友達と約束があります。','exampleMeaning':'친구와 약속이 있습니다.'},
  {'jp':'用事','reading':'ようじ','meaning':'볼일','pos':'명사','example':'今日は用事があります。','exampleMeaning':'오늘은 볼일이 있습니다.'},
  {'jp':'理由','reading':'りゆう','meaning':'이유','pos':'명사','example':'理由を教えてください。','exampleMeaning':'이유를 알려 주세요.'},
  {'jp':'利用','reading':'りよう','meaning':'이용','pos':'명사','example':'図書館を利用します。','exampleMeaning':'도서관을 이용합니다.'},
  {'jp':'歴史','reading':'れきし','meaning':'역사','pos':'명사','example':'日本の歴史を学びます。','exampleMeaning':'일본의 역사를 배웁니다.'},
  {'jp':'連絡','reading':'れんらく','meaning':'연락','pos':'명사','example':'後で連絡します。','exampleMeaning':'나중에 연락하겠습니다.'},
  {'jp':'冷蔵庫','reading':'れいぞうこ','meaning':'냉장고','pos':'명사','example':'牛乳は冷蔵庫にあります。','exampleMeaning':'우유는 냉장고에 있습니다.'},
  {'jp':'留守','reading':'るす','meaning':'부재중','pos':'명사','example':'母は留守です。','exampleMeaning':'어머니는 집에 안 계십니다。'},
  {'jp':'特別','reading':'とくべつ','meaning':'특별함','pos':'な형용사','example':'今日は特別な日です。','exampleMeaning':'오늘은 특별한 날입니다.'},
  {'jp':'必要','reading':'ひつよう','meaning':'필요함','pos':'な형용사','example':'パスポートが必要です。','exampleMeaning':'여권이 필요합니다.'},
  {'jp':'複雑','reading':'ふくざつ','meaning':'복잡함','pos':'な형용사','example':'この問題は複雑です。','exampleMeaning':'이 문제는 복잡합니다.'},
  {'jp':'十分','reading':'じゅうぶん','meaning':'충분함','pos':'な형용사','example':'時間は十分あります。','exampleMeaning':'시간은 충분히 있습니다。'},
  {'jp':'熱心','reading':'ねっしん','meaning':'열심임','pos':'な형용사','example':'彼は勉強に熱心です。','exampleMeaning':'그는 공부에 열심입니다.'},
  {'jp':'急','reading':'きゅう','meaning':'급함','pos':'な형용사','example':'急な用事ができました。','exampleMeaning':'갑작스러운 볼일이 생겼습니다.'},
  {'jp':'珍しい','reading':'めずらしい','meaning':'드물다, 희귀하다','pos':'い형용사','example':'珍しい鳥を見ました。','exampleMeaning':'희귀한 새를 보았습니다.'},
  {'jp':'厳しい','reading':'きびしい','meaning':'엄격하다, 혹독하다','pos':'い형용사','example':'先生は厳しいです。','exampleMeaning':'선생님은 엄격합니다.'},
  {'jp':'正しい','reading':'ただしい','meaning':'올바르다','pos':'い형용사','example':'正しい答えを選びます。','exampleMeaning':'올바른 답을 고릅니다.'},
  {'jp':'詳しい','reading':'くわしい','meaning':'자세하다, 잘 알다','pos':'い형용사','example':'彼は日本の歴史に詳しいです。','exampleMeaning':'그는 일본 역사에 대해 잘 압니다.'},
  {'jp':'深い','reading':'ふかい','meaning':'깊다','pos':'い형용사','example':'この川は深いです。','exampleMeaning':'이 강은 깊습니다.'},
  {'jp':'浅い','reading':'あさい','meaning':'얕다','pos':'い형용사','example':'この池は浅いです。','exampleMeaning':'이 연못은 얕습니다.'},
  {'jp':'苦い','reading':'にがい','meaning':'쓰다','pos':'い형용사','example':'この薬は苦いです。','exampleMeaning':'이 약은 씁니다.'},
  {'jp':'柔らかい','reading':'やわらかい','meaning':'부드럽다','pos':'い형용사','example':'このパンは柔らかいです。','exampleMeaning':'이 빵은 부드럽습니다.'},
  {'jp':'硬い','reading':'かたい','meaning':'딱딱하다','pos':'い형용사','example':'この肉は硬いです。','exampleMeaning':'이 고기는 딱딱합니다.'},
  {'jp':'細かい','reading':'こまかい','meaning':'잘다, 세밀하다','pos':'い형용사','example':'細かいお金がありますか。','exampleMeaning':'잔돈이 있나요?'},
  {'jp':'眠い','reading':'ねむい','meaning':'졸리다','pos':'い형용사','example':'今日はとても眠いです。','exampleMeaning':'오늘은 매우 졸립니다.'},
  {'jp':'恥ずかしい','reading':'はずかしい','meaning':'부끄럽다','pos':'い형용사','example':'人の前で話すのは恥ずかしいです。','exampleMeaning':'사람들 앞에서 말하는 것은 부끄럽습니다.'},
  {'jp':'寂しい','reading':'さびしい','meaning':'외롭다','pos':'い형용사','example':'一人でいると寂しいです。','exampleMeaning':'혼자 있으면 외롭습니다.'},
  {'jp':'嬉しい','reading':'うれしい','meaning':'기쁘다','pos':'い형용사','example':'プレゼントをもらって嬉しいです。','exampleMeaning':'선물을 받아서 기쁩니다.'},
  {'jp':'悲しい','reading':'かなしい','meaning':'슬프다','pos':'い형용사','example':'悲しいニュースを聞きました。','exampleMeaning':'슬픈 소식을 들었습니다.'},
  {'jp':'危険','reading':'きけん','meaning':'위험함','pos':'な형용사','example':'ここは危険です。','exampleMeaning':'이곳은 위험합니다.'},
  {'jp':'安全','reading':'あんぜん','meaning':'안전함','pos':'な형용사','example':'安全な場所に行きましょう。','exampleMeaning':'안전한 장소로 갑시다.'},];

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
