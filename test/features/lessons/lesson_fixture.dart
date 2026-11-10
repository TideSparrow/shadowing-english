import 'package:common_learn_english/features/lessons/domain/intensive_lesson.dart';

const LessonSource lessonSource = LessonSource(
  episodeId: 'lesson-fixture-episode',
  courseTitle: '家庭日常 · 演示素材',
  episodeTitle: '早餐时间',
  startMs: 53000,
  endMs: 56500,
  english: 'Phil, would you get them?',
  context:
      '[50000-52000] Breakfast is ready.\n[53000-56500] Phil, would you get them?',
  boundaryLimited: false,
);

Map<String, dynamic> lessonContent() => <String, dynamic>{
  'meaning': '菲尔，你去叫他们过来，好吗？',
  'scene': '前一句说“早餐准备好了”，接着请菲尔去叫人过来。字幕没有说明 them 具体指谁，译文保留“他们”。',
  'cards': <Map<String, dynamic>>[
    <String, dynamic>{
      'kind': 'scene',
      'focus': 'get them',
      'pattern': 'get someone',
      'meaning': '去叫某人／把某人找来',
      'explanation': '前一句说早餐准备好了，现在需要把人叫来。因此 get them 是请菲尔去叫他们过来，而不是让他“得到他们”。',
      'tip': '这里的 get 不是“得到”；them 指谁，字幕没有交代。',
      'examples': <Map<String, String>>[
        <String, String>{
          'situation': '饭做好了，请家人叫孩子过来',
          'english': 'Can you get the kids?',
          'chinese': '你去叫孩子们过来，好吗？',
        },
        <String, String>{
          'situation': '同事在找人，你主动去叫',
          'english': 'I’ll get him.',
          'chinese': '我去叫他。',
        },
      ],
      'speech': <Map<String, String>>[
        <String, String>{
          'language': 'en-US',
          'text': 'Phil, would you get them?',
        },
        <String, String>{
          'language': 'zh-CN',
          'text':
              '菲尔，你去叫他们过来，好吗？前一句说早餐准备好了，所以这里的 get someone 表示去叫某人，把人找来。字幕没有说明他们是谁。',
        },
        <String, String>{'language': 'zh-CN', 'text': '饭做好了，请家人叫孩子过来，可以说：'},
        <String, String>{'language': 'en-US', 'text': 'Can you get the kids?'},
        <String, String>{
          'language': 'zh-CN',
          'text': '你去叫孩子们过来，好吗？同事在找人，你主动去叫，可以说：',
        },
        <String, String>{'language': 'en-US', 'text': 'I’ll get him.'},
        <String, String>{
          'language': 'zh-CN',
          'text': '我去叫他。记住这个具体动作，不要把 get 一律套成得到。',
        },
      ],
    },
    <String, dynamic>{
      'kind': 'expression',
      'focus': 'would you',
      'pattern': 'would you + 动词原形',
      'meaning': '请对方帮忙做某事',
      'explanation':
          '说话人叫出 Phil 的名字，再请他去叫人。Would you 在这里引出请求，中文用“你……好吗”更自然，不必逐字译成“你会不会”。',
      'tip': '这里是在请人帮忙，不是在预测他“会不会”去。',
      'examples': <Map<String, String>>[
        <String, String>{
          'situation': '门口有风，请对方关门',
          'english': 'Would you close the door?',
          'chinese': '帮我关一下门，好吗？',
        },
        <String, String>{
          'situation': '够不到盐，请同桌递一下',
          'english': 'Would you pass me the salt?',
          'chinese': '把盐递给我一下，好吗？',
        },
      ],
      'speech': <Map<String, String>>[
        <String, String>{'language': 'en-US', 'text': 'Would you get them?'},
        <String, String>{
          'language': 'zh-CN',
          'text':
              '这里 would you 加动词原形，是请对方帮忙。说话人叫出菲尔的名字，让他去叫人，所以译成你去叫他们过来好吗。不是在预测未来。',
        },
        <String, String>{'language': 'zh-CN', 'text': '门口有风，请对方关门：'},
        <String, String>{
          'language': 'en-US',
          'text': 'Would you close the door?',
        },
        <String, String>{'language': 'zh-CN', 'text': '帮我关一下门，好吗？够不到盐，请同桌递一下：'},
        <String, String>{
          'language': 'en-US',
          'text': 'Would you pass me the salt?',
        },
        <String, String>{'language': 'zh-CN', 'text': '把盐递给我一下，好吗？这两句都在发出请求。'},
      ],
    },
    <String, dynamic>{
      'kind': 'usage',
      'focus': 'get someone',
      'pattern': 'get someone (for me)',
      'meaning': '（帮我）叫一下某人／把人找来',
      'explanation':
          '办公室里找人、家里叫人接电话，也能用这个表达。for me 说明是帮我做这件事。若语境变成去机场接人，get someone 就可能表示“接某人”。',
      'tip': '“叫来”适合这里的场景，换成接机场的人就可能是“去接”。',
      'examples': <Map<String, String>>[
        <String, String>{
          'situation': '办公室需要找约翰商量事情',
          'english': 'Can you get John for me?',
          'chinese': '你能帮我叫一下约翰吗？',
        },
        <String, String>{
          'situation': '有人打电话找爸爸，请家人去叫',
          'english': 'Could you get Dad? He has a phone call.',
          'chinese': '帮忙叫一下爸爸好吗？有人打电话找他。',
        },
      ],
      'speech': <Map<String, String>>[
        <String, String>{'language': 'en-US', 'text': 'Get someone for me.'},
        <String, String>{
          'language': 'zh-CN',
          'text': '在找人来帮忙的场景里，这表示帮我叫一下某人。办公室需要找约翰商量事情，可以说：',
        },
        <String, String>{
          'language': 'en-US',
          'text': 'Can you get John for me?',
        },
        <String, String>{
          'language': 'zh-CN',
          'text': '你能帮我叫一下约翰吗？有人打电话找爸爸，请家人去叫，可以说：',
        },
        <String, String>{
          'language': 'en-US',
          'text': 'Could you get Dad? He has a phone call.',
        },
        <String, String>{
          'language': 'zh-CN',
          'text': '帮忙叫一下爸爸好吗？有人打电话找他。叫来适合这两个场景；如果是去机场接人，同样的搭配就可能表示去接。',
        },
      ],
    },
  ],
};

IntensiveLesson fixtureLesson({
  LessonSource source = lessonSource,
  LessonTokenUsage? usage,
}) => IntensiveLesson.fromContent(
  source: source,
  json: lessonContent(),
  usage: usage,
  createdAt: DateTime.utc(2026, 11, 10),
);

IntensiveLesson numberedLesson(int index, {String course = '家庭日常'}) =>
    fixtureLesson(
      source: LessonSource(
        episodeId: lessonSource.episodeId,
        courseTitle: course,
        episodeTitle: '示例 $index',
        startMs: index * 1000,
        endMs: index * 1000 + 900,
        english: index == 52
            ? 'A searchable needle on the last page.'
            : 'Example sentence $index.',
        context: lessonSource.context,
        boundaryLimited: false,
      ),
    );
