import '../../helpers/fake_backend.dart';
import '../../helpers/harness.dart';

/// Store item JSON (`ProfilePicture`) shaped like the real manifest rows.
Map<String, dynamic> storeItemJson(
  int i, {
  String? name,
  bool lottie = true,
  int? price,
  bool owned = false,
  bool equipped = false,
}) {
  final slug = 'item-$i';
  return {
    'id': 'pp_item_$i',
    'name': name ?? 'Item $i',
    'format': lottie ? 'lottie' : 'image',
    'path': lottie
        ? 'profile_pictures/lottie_animation/$slug.json'
        : 'profile_pictures/image/$slug.png',
    'price': {'diamonds': price ?? 5 + i % 46},
    'owned': owned,
    'equipped': equipped,
  };
}

/// The test shelf: 30 pictures. #1 owned, #2 owned and equipped, #3 costs
/// 60 diamonds (the test wallet has 50), long names on #4 and #5.
List<Map<String, dynamic>> storeShelf() => [
  for (var i = 0; i < 30; i++)
    storeItemJson(
      i,
      lottie: i % 5 != 0,
      name: switch (i) {
        4 => 'Turtle Holding Board',
        5 => 'Laughing Dinosaur 2',
        _ => null,
      },
      price: switch (i) {
        0 => 10,
        3 => 60,
        _ => null,
      },
      owned: i == 1 || i == 2,
      equipped: i == 2,
    ),
];

Map<String, dynamic> storePageJson(
  List<Map<String, dynamic>> items, {
  String? nextCursor,
  int? total,
  String? equipped = 'pp_item_2',
}) => {
  'items': items,
  'nextCursor': nextCursor,
  'total': total ?? items.length,
  'equipped': equipped,
};

/// `GET /store/profile-pictures` over [shelf], paged by [pageSize] with
/// cursors `c<offset>`, honouring the filter and `excludeOwned` (the
/// Shop's shelf). `filter=owned&excludeOwned=true` is a 400 like the
/// server.
void routeStore(
  TestEnv env, {
  List<Map<String, dynamic>>? shelf,
  int pageSize = 24,
}) {
  final all = shelf ?? storeShelf();
  final equipped = [
    for (final i in all)
      if (i['equipped'] == true) i['id'] as String,
  ].firstOrNull;
  env.backend.on('GET', '/store/profile-pictures', (req) {
    final filter = req.query['filter'] ?? 'all';
    final excludeOwned = req.query['excludeOwned'] == 'true';
    if (excludeOwned && filter == 'owned') {
      return FakeResponse.error(400, 'bad_request');
    }
    final items = [
      for (final i in all)
        if (!(excludeOwned && i['owned'] == true) &&
            switch (filter) {
              'animated' => i['format'] == 'lottie',
              'static' => i['format'] == 'image',
              'owned' => i['owned'] == true,
              _ => true,
            })
          i,
    ];
    final cursor = req.query['cursor'] as String?;
    final start = cursor == null ? 0 : int.parse(cursor.substring(1));
    final end = (start + pageSize).clamp(0, items.length);
    return FakeResponse(
      200,
      storePageJson(
        items.sublist(start, end),
        nextCursor: end < items.length ? 'c$end' : null,
        total: items.length,
        equipped: equipped,
      ),
    );
  });
}
