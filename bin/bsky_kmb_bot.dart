import 'dart:io';
import 'dart:math';

import 'package:bluesky/bluesky.dart' as bluesky;
import 'package:bluesky_text/bluesky_text.dart';
import 'package:cron/cron.dart';
import 'package:http/http.dart' as http;
import 'package:fullwidth_halfwidth_converter/fullwidth_halfwidth_converter.dart';

late final String myDid;
late final bluesky.Bluesky bsky;
final _follows = <String, bluesky.AtUri>{};
final rand = Random();
final cron = Cron();

Future<void> main(List<String> arguments) async {
  final identifier = Platform.environment["BSKY_KMB_BOT_ID"];
  final password = Platform.environment["BSKY_KMB_BOT_PW"];
  if (identifier == null || password == null) {
    throw Exception("BSKY_KMB_BOT_ID and BSKY_KMB_BOT_PW must be set");
  }
  print("Logging in as $identifier");
  final session =
      await bluesky.createSession(identifier: identifier, password: password);
  bsky = bluesky.Bluesky.fromSession(session.data);
  {
    print("Resolving handle...");
    final me = await bsky.identity.resolveHandle(handle: identifier);
    myDid = me.data.did;
    print("I am $myDid");
  }
  {
    cron.schedule(Schedule.parse("0 * * * *"), changeIcon);
  }
  {
    print("Getting following...");
    String? cursor;
    while (true) {
      print("Getting following with cursor $cursor");
      final follows = await bsky.graph.getFollows(
        actor: myDid,
        limit: 100,
        cursor: cursor,
      );
      if (follows.data.follows.isEmpty) break;
      for (final follow in follows.data.follows) {
        _follows[follow.did] = follow.viewer.following!;
      }
      cursor = follows.data.cursor;
      if (cursor == null) break;
    }
  }
  while (true) {
    final subscribe = await bsky.sync.subscribeRepos();

    print("Listening to commits...");
    await for (final event in subscribe.data.stream) {
      event.when(
        commit: repoCommitAdapter.execute,
        handle: (data) {},
        migrate: (data) {},
        tombstone: (data) {},
        info: (data) {},
        unknown: (data) {},
      );
    }
    print("Reconnecting...");
  }
}

final repoCommitAdapter = bluesky.RepoCommitAdaptor(
  onCreateFollow: (data) async {
    if (data.record.did != myDid) return;
    print("Followed by ${data.author}");
    final follow = await bsky.graph.follow(did: data.author);
    _follows[data.author] = follow.data.uri;
    print("Followed back ${follow.data.uri}");
  },
  onCreateBlock: (data) async {
    if (data.record.did != myDid) return;
    print("Blocked by ${data.author}");
    final uri = _follows.remove(data.author);
    if (uri == null) return;
    await bsky.repo.deleteRecord(uri: uri);
    print("Removed following $uri");
  },
  onCreatePost: (data) async {
    if (!_follows.containsKey(data.author)) return;
    print("Posted ${data.cid} from (${data.author})");
    final profile = await bsky.actor.getProfile(actor: data.author);
    final count = profile.data.postsCount;
    if (count != 0 && count % 686 == 0) {
      print("Sending a message to ${data.author}");
      final text = makeText(count, profile.data);
      final strongRef = data.toStrongRef();
      final post = await bsky.feed.post(
        text: text.value,
        facets: (await text.entities.toFacets())
            .map(bluesky.Facet.fromJson)
            .toList(),
        reply: bluesky.ReplyRef(root: strongRef, parent: strongRef),
      );
      print("Posted ${post.data.uri}");
    }
    // chekc is kmb related post
    {
      final text = data.record.text
          .toHalfwidth(
            convertSymbol: true,
            convertAlphabet: true,
            convertNumber: true,
            convertKana: false,
          )
          .toLowerCase();
      for (final favorite in favorites) {
        if (text.contains(favorite)) {
          print("Favorite found");
          await bsky.feed.like(cid: data.cid, uri: data.uri);
          print("Liked ${data.uri}");
          break;
        }
      }
    }
  },
);

BlueskyText makeText(int count, bluesky.ActorProfile profile) {
  final killme = count ~/ 686;
  final flavor = makeFlavor(killme);
  final username = profile.handle;
  return BlueskyText(
      "@$username さんが、投稿数: $count\n($killmeキルミー) に到達したよ！！\n$flavor");
}

String makeFlavor(int killme) {
  if (killme == 686) return "あなたがカヅホ神ですか！？";
  if (killme == 143) return "後ろに、なにかが……"; // Mari...
  if (killme % 10 == 0) {
    return majires[rand.nextInt(majires.length)];
  }
  return ohome[rand.nextInt(ohome.length)];
}

Future<void> changeIcon() async {
  print("Changing icon...");
  final icon = i686[rand.nextInt(i686.length)];
  final url = "http://aka.saintpillia.com/killme/icon/$icon.png";
  print("Downloading $url");
  final response = await http.get(Uri.parse(url));
  print("Uploading icon...");
  final blob = await bsky.repo.uploadBlob(response.bodyBytes);

  final old = await bsky.actor.getProfile(actor: myDid);
  await bsky.actor.profile(
    displayName: old.data.displayName,
    avatar: blob.data.blob,
    description: old.data.description,
  );
  print("Changed profile!!");
}

final ohome = [
  "やるぅ！",
  "ナイスですね～",
  "足が！",
  "すごい！",
  "まって～",
  "では、忠誠の誓いを",
  "こそばゆい～",
  "いいこと思いついた！",
  "やった～！",
  "わ～いわ～い！！",
  "いつまでふたりでいるのかな",
  "おいしくできたらいただきます",
  "しらないままでもいいのかな",
  "ほんとのきもちはひみつだよ",
  "どこまでふたりでいるのかな",
  "ものまねすきるがみじゅくなの",
  "たのしいじかんがいいのかな",
  "ほんとのきもちはひみつだよ",
  "このままふたりでいるのかな",
  "ほとぼりさめたらこんにちは",
  "おとなになるまでいいのかな",
  "ほんとのきもちはひみつだよ",
];

final majires = [
  "今は超能力の話をしてるんだよ…",
  "え？超能力じゃないじゃん…",
  "何やってんの！？こんなんでハチ防げると思ってるの？",
  "もう、大きな声出したらダメだよ。バカと思われちゃうよ！",
  "こんなことダーツのうまさとは関係ないよ。何やらせるの？",
  "風邪ひいてるのに勉強とか、何言ってんの？",
  "何いきなり飛び込んでるの！",
  "何言ってんの。もうお金も払ったし。",
  "いきなりヒーローとか何言ってんの？…大丈夫？",
];

final favorites = [
  "きるみー",
  "キルミー",
  "killmebaby",
  "kill me baby",
  "kmb",
  "やすな",
  "ヤスナ",
  "そーにゃ",
  "ソーニャ",
  "あぎり",
  "アギリ",
  "没キャラ",
  "没きゃら",
  "愛殺寶貝",
  "686",
  "六八六",
  "六百八十六",
  "六百八拾六",
  "dclxxxvi",
  "わさわさ",
  "ワサワサ",
];

final i686 = [
  "01_001",
  "01_091",
  "02_076",
  "04_031",
  "05_035",
  "07_021",
  "09_009",
  "10_019",
  "10_102",
  "11_043",
  "01_003",
  "01_092",
  "02_077",
  "04_032",
  "05_036",
  "07_023",
  "09_010",
  "10_020",
  "10_104",
  "11_044",
  "01_005",
  "026",
  "03_001",
  "04_033",
  "05_037",
  "07_024",
  "09_011",
  "10_021",
  "10_105",
  "11_045",
  "01_006",
  "02_001",
  "03_002",
  "04_034",
  "05_038",
  "07_025",
  "09_012",
  "10_022",
  "10_106",
  "11_046",
  "01_008",
  "02_002",
  "03_004",
  "04_035",
  "05_040",
  "07_026",
  "09_013",
  "10_023",
  "10_107",
  "11_047",
  "01_009",
  "02_003",
  "03_007",
  "04_036",
  "05_041",
  "07_027",
  "09_016",
  "10_024",
  "10_111",
  "11_048",
  "01_011",
  "02_004",
  "03_008",
  "04_037",
  "05_042",
  "07_028",
  "09_017",
  "10_025",
  "10_112",
  "11_049",
  "01_012",
  "02_005",
  "03_010",
  "04_038",
  "05_044",
  "07_029",
  "09_018",
  "10_026",
  "10_115",
  "11_050",
  "01_015",
  "02_006",
  "03_011",
  "04_039",
  "05_046",
  "07_033",
  "09_019",
  "10_027",
  "10_116",
  "11_052",
  "01_017",
  "02_007",
  "03_012",
  "04_040",
  "05_047",
  "07_034",
  "09_020",
  "10_028",
  "10_117",
  "11_053",
  "01_019",
  "02_008",
  "03_013",
  "04_041",
  "05_048",
  "07_035",
  "09_022",
  "10_029",
  "10_120",
  "11_054",
  "01_021",
  "02_010",
  "03_014",
  "04_042",
  "05_049",
  "07_036",
  "09_023",
  "10_032",
  "10_121",
  "11_055",
  "01_022",
  "02_011",
  "03_015",
  "04_043",
  "05_050",
  "07_037",
  "09_024",
  "10_034",
  "10_122",
  "11_056",
  "01_024",
  "02_012",
  "03_016",
  "04_044",
  "05_051",
  "07_038",
  "09_027",
  "10_035",
  "10_125",
  "11_057",
  "01_025",
  "02_013",
  "03_017",
  "04_045",
  "05_052",
  "07_039",
  "09_028",
  "10_036",
  "10_126",
  "11_059",
  "01_026",
  "02_014",
  "03_018",
  "04_046",
  "05_053",
  "07_040",
  "09_030",
  "10_037",
  "10_127",
  "11_060",
  "01_027",
  "02_015",
  "03_019",
  "04_047",
  "05_054",
  "07_042",
  "09_031",
  "10_038",
  "10_130",
  "11_063",
  "01_029",
  "02_016",
  "03_021",
  "04_048",
  "05_055",
  "07_043",
  "09_032",
  "10_039",
  "10_131",
  "11_064",
  "01_031",
  "02_017",
  "03_022",
  "04_049",
  "05_057",
  "07_044",
  "09_033",
  "10_040",
  "10_132",
  "11_065",
  "01_032",
  "02_018",
  "03_023",
  "04_050",
  "05_058",
  "07_045",
  "09_034",
  "10_041",
  "10_133",
  "11_067",
  "01_033",
  "02_019",
  "03_024",
  "04_051",
  "06_003",
  "07_046",
  "09_035",
  "10_042",
  "10_134",
  "11_068",
  "01_034",
  "02_020",
  "03_025",
  "04_052",
  "06_005",
  "07_047",
  "09_036",
  "10_043",
  "10_135",
  "11_069",
  "01_035",
  "02_021",
  "03_026",
  "04_053",
  "06_007",
  "07_048",
  "09_037",
  "10_044",
  "10_136",
  "12_001",
  "01_037",
  "02_022",
  "03_027",
  "04_054",
  "06_008",
  "07_049",
  "09_038",
  "10_045",
  "10_137",
  "12_002",
  "01_038",
  "02_023",
  "03_028",
  "04_055",
  "06_011",
  "07_050",
  "09_039",
  "10_046",
  "10_138",
  "12_004",
  "01_039",
  "02_024",
  "03_029",
  "04_056",
  "06_012",
  "07_051",
  "09_040",
  "10_047",
  "10_139",
  "12_005",
  "01_041",
  "02_025",
  "03_030",
  "04_057",
  "06_013",
  "07_052",
  "09_041",
  "10_049",
  "10_141",
  "12_006",
  "01_042",
  "02_026",
  "03_031",
  "04_058",
  "06_014",
  "07_053",
  "09_042",
  "10_050",
  "10_142",
  "12_010",
  "01_043",
  "02_027",
  "03_032",
  "04_059",
  "06_015",
  "07_054",
  "09_043",
  "10_051",
  "10_143",
  "12_013",
  "01_044",
  "02_028",
  "03_033",
  "04_060",
  "06_016",
  "07_055",
  "09_044",
  "10_052",
  "10_144",
  "12_014",
  "01_045",
  "02_029",
  "03_034",
  "04_061",
  "06_017",
  "07_056",
  "09_045",
  "10_053",
  "10_145",
  "12_016",
  "01_046",
  "02_030",
  "03_035",
  "04_062",
  "06_018",
  "07_057",
  "09_046",
  "10_054",
  "11_001",
  "12_017",
  "01_047",
  "02_031",
  "03_036",
  "04_063",
  "06_019",
  "07_058",
  "09_048",
  "10_055",
  "11_002",
  "12_018",
  "01_048",
  "02_032",
  "03_037",
  "04_064",
  "06_020",
  "07_059",
  "09_050",
  "10_058",
  "11_003",
  "12_019",
  "01_049",
  "02_033",
  "03_038",
  "04_065",
  "06_022",
  "07_060",
  "09_051",
  "10_059",
  "11_004",
  "12_020",
  "01_050",
  "02_034",
  "03_039",
  "04_066",
  "06_023",
  "07_061",
  "09_053",
  "10_061",
  "11_006",
  "12_023",
  "01_051",
  "02_035",
  "03_040",
  "04_067",
  "06_024",
  "07_062",
  "09_054",
  "10_062",
  "11_007",
  "12_024",
  "01_052",
  "02_036",
  "03_041",
  "04_068",
  "06_025",
  "07_063",
  "09_055",
  "10_063",
  "11_008",
  "12_026",
  "01_053",
  "02_037",
  "03_042",
  "04_069",
  "06_027",
  "07_064",
  "09_057",
  "10_064",
  "11_009",
  "12_027",
  "01_054",
  "02_038",
  "03_044",
  "05_001",
  "06_028",
  "07_065",
  "09_059",
  "10_065",
  "11_010",
  "12_028",
  "01_055",
  "02_039",
  "03_045",
  "05_002",
  "06_029",
  "07_066",
  "09_060",
  "10_066",
  "11_011",
  "12_030",
  "01_056",
  "02_040",
  "03_046",
  "05_003",
  "06_030",
  "07_067",
  "09_061",
  "10_067",
  "11_012",
  "12_031",
  "01_057",
  "02_041",
  "03_047",
  "05_004",
  "06_031",
  "07_069",
  "09_063",
  "10_068",
  "11_013",
  "12_032",
  "01_058",
  "02_042",
  "03_048",
  "05_005",
  "06_032",
  "07_071",
  "09_064",
  "10_071",
  "11_016",
  "12_033",
  "01_059",
  "02_043",
  "03_049",
  "05_006",
  "06_033",
  "07_072",
  "09_065",
  "10_072",
  "11_017",
  "12_034",
  "01_060",
  "02_044",
  "03_050",
  "05_007",
  "06_034",
  "07_073",
  "09_066",
  "10_073",
  "11_019",
  "12_035",
  "01_061",
  "02_046",
  "03_051",
  "05_008",
  "06_035",
  "07_074",
  "09_067",
  "10_074",
  "11_020",
  "12_039",
  "01_062",
  "02_048",
  "03_052",
  "05_009",
  "06_036",
  "08_001",
  "09_068",
  "10_075",
  "11_021",
  "12_042",
  "01_063",
  "02_049",
  "03_055",
  "05_010",
  "06_038",
  "08_002",
  "09_069",
  "10_077",
  "11_022",
  "12_043",
  "01_064",
  "02_050",
  "03_056",
  "05_011",
  "06_039",
  "08_003",
  "09_070",
  "10_078",
  "11_023",
  "12_044",
  "01_065",
  "02_051",
  "03_058",
  "05_012",
  "06_040",
  "08_004",
  "09_071",
  "10_079",
  "11_024",
  "12_045",
  "01_066",
  "02_052",
  "03_060",
  "05_013",
  "07_001",
  "08_005",
  "09_072",
  "10_080",
  "11_025",
  "12_046",
  "01_067",
  "02_053",
  "03_061",
  "05_014",
  "07_002",
  "08_006",
  "09_073",
  "10_082",
  "11_026",
  "12_047",
  "01_068",
  "02_055",
  "03_062",
  "05_015",
  "07_003",
  "08_007",
  "09_074",
  "10_083",
  "11_027",
  "12_048",
  "01_070",
  "02_058",
  "03_063",
  "05_016",
  "07_004",
  "08_009",
  "10_001",
  "10_084",
  "11_028",
  "12_049",
  "01_071",
  "02_059",
  "03_064",
  "05_017",
  "07_005",
  "08_010",
  "10_003",
  "10_085",
  "11_029",
  "12_050",
  "01_073",
  "02_060",
  "03_065",
  "05_018",
  "07_006",
  "08_013",
  "10_004",
  "10_086",
  "11_03",
  "12_052",
  "01_075",
  "02_061",
  "03_066",
  "05_019",
  "07_007",
  "08_014",
  "10_005",
  "10_087",
  "11_030",
  "12_054",
  "01_076",
  "02_062",
  "03_067",
  "05_020",
  "07_008",
  "08_015",
  "10_006",
  "10_088",
  "11_031",
  "12_055",
  "01_077",
  "02_064",
  "03_068",
  "05_022",
  "07_009",
  "08_016",
  "10_007",
  "10_089",
  "11_032",
  "12_056",
  "01_078",
  "02_065",
  "03_069",
  "05_023",
  "07_010",
  "08_017",
  "10_008",
  "10_090",
  "11_033",
  "12_060",
  "01_082",
  "02_066",
  "03_070",
  "05_026",
  "07_012",
  "08_018",
  "10_009",
  "10_092",
  "11_034",
  "12_061",
  "01_084",
  "02_067",
  "04_019",
  "05_027",
  "07_014",
  "08_019",
  "10_010",
  "10_093",
  "11_036",
  "12_062",
  "01_085",
  "02_068",
  "04_022",
  "05_028",
  "07_015",
  "08_020",
  "10_011",
  "10_094",
  "11_037",
  "12_063",
  "01_086",
  "02_069",
  "04_023",
  "05_029",
  "07_016",
  "09_001",
  "10_012",
  "10_095",
  "11_038",
  "140",
  "01_087",
  "02_070",
  "04_024",
  "05_030",
  "07_017",
  "09_003",
  "10_015",
  "10_096",
  "11_039",
  "01_088",
  "02_071",
  "04_028",
  "05_031",
  "07_018",
  "09_004",
  "10_016",
  "10_099",
  "11_040",
  "01_089",
  "02_072",
  "04_029",
  "05_033",
  "07_019",
  "09_007",
  "10_017",
  "10_100",
  "11_041",
  "01_090",
  "02_073",
  "04_030",
  "05_034",
  "07_020",
  "09_008",
  "10_018",
  "10_101",
  "11_042",
];
