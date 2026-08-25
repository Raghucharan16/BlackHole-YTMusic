/*
 *  This file is part of BlackHole (https://github.com/Sangwan5688/BlackHole).
 * 
 * BlackHole is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * BlackHole is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with BlackHole.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Copyright (c) 2021-2022, Ankit Sangwan
 */

import 'dart:convert';

import 'package:blackhole/Helpers/extensions.dart';
import 'package:blackhole/Services/youtube_services.dart';
import 'package:blackhole/Services/ytmusic/nav.dart';
import 'package:blackhole/Services/ytmusic/playlist.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YtMusicService {
  static const ytmDomain = 'music.youtube.com';
  static const httpsYtmDomain = 'https://music.youtube.com';
  static const baseApiEndpoint = '/youtubei/v1/';
  static const ytmParams = {
    'alt': 'json',
    'key': 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30'
  };
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:88.0) Gecko/20100101 Firefox/88.0';
  static const Map<String, String> endpoints = {
    'search': 'search',
    'browse': 'browse',
    'get_song': 'player',
    'get_playlist': 'playlist',
    'get_album': 'album',
    'get_artist': 'artist',
    'get_video': 'video',
    'get_channel': 'channel',
    'get_lyrics': 'lyrics',
    'search_suggestions': 'music/get_search_suggestions',
    'next': 'next',
  };
  static const filters = [
    'albums',
    'artists',
    'playlists',
    'community_playlists',
    'featured_playlists',
    'songs',
    'videos'
  ];
  static const scopes = ['library', 'uploads'];

  Map<String, String>? headers;
  int? signatureTimestamp;
  Map<String, dynamic>? context;

  // Temporary diagnostic: last error/status seen while loading the home feed.
  static String lastHomeDiag = '';

  static final YtMusicService _singleton = YtMusicService._internal();

  factory YtMusicService() {
    return _singleton;
  }

  YtMusicService._internal();

  Map<String, String> initializeHeaders() {
    return {
      'user-agent': userAgent,
      'accept': '*/*',
      'content-type': 'application/json',
      'origin': httpsYtmDomain,
      'cookie': 'CONSENT=YES+1'
    };
  }

  Future<Response> sendGetRequest(
    String url,
    Map<String, String>? headers,
  ) async {
    final Uri uri = Uri.https(url);
    final Response response = await get(uri, headers: headers);
    return response;
  }

  Future<String?> getVisitorId(Map<String, String>? headers) async {
    final response = await sendGetRequest(ytmDomain, headers);
    final reg = RegExp(r'ytcfg\.set\s*\(\s*({.+?})\s*\)\s*;');
    final matches = reg.firstMatch(response.body);
    String? visitorId;
    if (matches != null) {
      final ytcfg = json.decode(matches.group(1).toString());
      visitorId = ytcfg['VISITOR_DATA']?.toString();
    }
    return visitorId;
  }

  Map<String, dynamic> initializeContext() {
    final DateTime now = DateTime.now();
    final String year = now.year.toString();
    final String month = now.month.toString().padLeft(2, '0');
    final String day = now.day.toString().padLeft(2, '0');
    final String date = year + month + day;
    return {
      'context': {
        'client': {'clientName': 'WEB_REMIX', 'clientVersion': '1.$date.01.00'},
        'user': {}
      }
    };
  }

  Future<Map> sendRequest(
    String endpoint,
    Map body,
    Map<String, String>? headers,
  ) async {
    final Uri uri = Uri.https(ytmDomain, baseApiEndpoint + endpoint, ytmParams);
    final response = await post(uri, headers: headers, body: jsonEncode(body));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map;
    } else {
      Logger.root
          .severe('YtMusic returned ${response.statusCode}', response.body);
      Logger.root.info('Requested endpoint: $uri');
      return {};
    }
  }

  String? getParam2(String filter) {
    final filterParams = {
      'songs': 'I',
      'videos': 'Q',
      'albums': 'Y',
      'artists': 'g',
      'playlists': 'o'
    };
    return filterParams[filter];
  }

  String? getSearchParams({
    String? filter,
    String? scope,
    bool ignoreSpelling = false,
  }) {
    String? params;
    String? param1;
    String? param2;
    String? param3;
    if (!ignoreSpelling && filter == null && scope == null) {
      return params;
    }

    if (scope == 'uploads') {
      params = 'agIYAw%3D%3D';
    }

    if (scope == 'library') {
      if (filter != null) {
        param1 = 'EgWKAQI';
        param2 = getParam2(filter);
        param3 = 'AWoKEAUQCRADEAoYBA%3D%3D';
      } else {
        params = 'agIYBA%3D%3D';
      }
    }

    if (scope == null && filter != null) {
      if (filter == 'playlists') {
        params = 'Eg-KAQwIABAAGAAgACgB';
        if (!ignoreSpelling) {
          params += 'MABqChAEEAMQCRAFEAo%3D';
        } else {
          params += 'MABCAggBagoQBBADEAkQBRAK';
        }
      } else {
        if (filter.contains('playlists')) {
          param1 = 'EgeKAQQoA';
          if (filter == 'featured_playlists') {
            param2 = 'Dg';
          } else {
            // community_playlists
            param2 = 'EA';
          }

          if (!ignoreSpelling) {
            param3 = 'BagwQDhAKEAMQBBAJEAU%3D';
          } else {
            param3 = 'BQgIIAWoMEA4QChADEAQQCRAF';
          }
        } else {
          param1 = 'EgWKAQI';
          param2 = getParam2(filter);
          if (!ignoreSpelling) {
            param3 = 'AWoMEA4QChADEAQQCRAF';
          } else {
            param3 = 'AUICCAFqDBAOEAoQAxAEEAkQBQ%3D%3D';
          }
        }
      }
    }

    if (scope == null && filter == null && ignoreSpelling) {
      params = 'EhGKAQ4IARABGAEgASgAOAFAAUICCAE%3D';
    }

    if (params != null) {
      return params;
    } else {
      return '$param1$param2$param3';
    }
  }

  Future<void> init() async {
    headers = initializeHeaders();
    if (!headers!.containsKey('X-Goog-Visitor-Id')) {
      headers!['X-Goog-Visitor-Id'] = await getVisitorId(headers) ?? '';
    }
    context = initializeContext();
    context!['context']['client']['hl'] = 'en';
  }

  // Fetches the YouTube Music home feed via the InnerTube browse API
  // (FEmusic_home). Returns the same shape the home screen expects:
  // {'body': [{'title': ..., 'playlists': [ items ]}], 'head': []}.
  Future<Map<String, List>> getMusicHome() async {
    if (headers == null) {
      await init();
    }
    try {
      final body = Map.from(context!);
      body['browseId'] = 'FEmusic_home';
      final res = await sendRequest(endpoints['browse']!, body, headers);
      final List sections = (nav(res, [
            'contents',
            'singleColumnBrowseResultsRenderer',
            'tabs',
            0,
            'tabRenderer',
            'content',
            'sectionListRenderer',
            'contents'
          ]) as List?) ??
          [];

      final List body_ = [];
      for (final section in sections) {
        final shelf = nav(section, ['musicCarouselShelfRenderer']);
        if (shelf == null) {
          continue;
        }
        final String shelfTitle = nav(shelf, [
              'header',
              'musicCarouselShelfBasicHeaderRenderer',
              'title',
              'runs',
              0,
              'text'
            ])?.toString() ??
            '';
        final List shelfItems = (nav(shelf, ['contents']) as List?) ?? [];
        final List playlists = [];
        for (final item in shelfItems) {
          final r = nav(item, ['musicTwoRowItemRenderer']);
          if (r == null) {
            continue;
          }
          final String title =
              nav(r, ['title', 'runs', 0, 'text'])?.toString() ?? '';
          final List subRuns =
              (nav(r, ['subtitle', 'runs']) as List?) ?? [];
          final String description =
              subRuns.map((e) => e['text']).join().toString();
          final List thumbs = (nav(r, [
                'thumbnailRenderer',
                'musicThumbnailRenderer',
                'thumbnail',
                'thumbnails'
              ]) as List?) ??
              [];
          final String image =
              thumbs.isNotEmpty ? thumbs.last['url'].toString() : '';
          final String imageMin =
              thumbs.isNotEmpty ? thumbs.first['url'].toString() : '';
          final String? videoId =
              nav(r, ['navigationEndpoint', 'watchEndpoint', 'videoId'])
                  ?.toString();
          final String? browseId =
              nav(r, ['navigationEndpoint', 'browseEndpoint', 'browseId'])
                  ?.toString();
          final String pageType = nav(r, [
                'navigationEndpoint',
                'browseEndpoint',
                'browseEndpointContextSupportedConfigs',
                'browseEndpointContextMusicConfig',
                'pageType'
              ])?.toString() ??
              '';

          String type;
          String id;
          if (videoId != null && videoId.isNotEmpty) {
            type = 'video';
            id = videoId;
          } else if (pageType.contains('ALBUM')) {
            type = 'album';
            id = browseId ?? '';
          } else if (pageType.contains('ARTIST')) {
            type = 'artist';
            id = browseId ?? '';
          } else {
            type = 'playlist';
            id = (browseId ?? '').replaceFirst('VL', '');
          }
          if (id.isEmpty) {
            continue;
          }
          playlists.add({
            'title': title,
            'type': type,
            'description': description,
            'count': '',
            'playlistId': id,
            'videoId': videoId ?? '',
            'firstItemId': videoId ?? '',
            'image': image,
            'imageMin': imageMin,
            'imageMedium': image,
            'imageStandard': image,
            'imageMax': image,
          });
        }
        if (playlists.isNotEmpty) {
          body_.add({'title': shelfTitle, 'playlists': playlists});
        }
      }
      if (body_.isEmpty) {
        lastHomeDiag = res.isEmpty
            ? 'YouTube Music browse returned no data'
            : 'no home shelves parsed (${sections.length} sections)';
      } else {
        lastHomeDiag = '';
      }
      return {'body': body_, 'head': []};
    } catch (e) {
      lastHomeDiag = 'parse error: $e';
      Logger.root.severe('Error in YtMusic getMusicHome: $e');
      return {'body': [], 'head': []};
    }
  }

  Future<List<Map>> search(
    String query, {
    String? scope,
    bool ignoreSpelling = false,
    String? filter,
  }) async {
    if (headers == null) {
      await init();
    }
    try {
      final body = Map.from(context!);
      body['query'] = query;
      final params = getSearchParams(
        filter: filter,
        scope: scope,
        ignoreSpelling: ignoreSpelling,
      );
      if (params != null) {
        body['params'] = params;
      }
      final List<Map> searchResults = [];
      final res = await sendRequest(endpoints['search']!, body, headers);
      if (!res.containsKey('contents')) {
        Logger.root.info('YtMusic returned no contents');
        return List.empty();
      }

      Map<String, dynamic> results = {};

      if ((res['contents'] as Map).containsKey('tabbedSearchResultsRenderer')) {
        final tabIndex =
            (scope == null || filter != null) ? 0 : scopes.indexOf(scope) + 1;
        results = nav(res, [
          'contents',
          'tabbedSearchResultsRenderer',
          'tabs',
          tabIndex,
          'tabRenderer',
          'content'
        ]) as Map<String, dynamic>;
      } else {
        Logger.root.info('tabbedSearchResultsRenderer not found');
        results = res['contents'] as Map<String, dynamic>;
      }

      final List finalResults =
          nav(results, ['sectionListRenderer', 'contents']) as List? ?? [];
      // Map an item's own type (from its subtitle) to a section name. YouTube
      // Music search no longer groups results under labelled
      // musicShelfRenderer sections; instead each result is a standalone
      // itemSectionRenderer, so we regroup by the per-item type.
      String sectionForType(String type) {
        final String t = type.trim().toLowerCase();
        if (t == 'video') return 'Videos';
        if (t == 'artist') return 'Artists';
        if (t == 'album' || t == 'single' || t == 'ep') return 'Albums';
        if (t.contains('playlist')) return 'Playlists';
        return 'Songs';
      }

      Map<String, dynamic>? parseItem(dynamic childItem) {
        final renderer = nav(childItem, ['musicResponsiveListItemRenderer']);
        if (renderer == null) {
          return null;
        }
        final List images = ((nav(renderer, [
                  'thumbnail',
                  'musicThumbnailRenderer',
                  'thumbnail',
                  'thumbnails'
                ]) as List?) ??
                [])
            .map((e) => e['url'])
            .toList();
        final String title = nav(renderer, [
              'flexColumns',
              0,
              'musicResponsiveListItemFlexColumnRenderer',
              'text',
              'runs',
              0,
              'text'
            ])?.toString() ??
            '';
        final List subtitleList = (nav(renderer, [
              'flexColumns',
              1,
              'musicResponsiveListItemFlexColumnRenderer',
              'text',
              'runs'
            ]) as List?) ??
            [];
        int count = 0;
        String type = '';
        String album = '';
        String artist = '';
        String views = '';
        String duration = '';
        String subtitle = '';
        String year = '';
        String countSongs = '';
        String subscribers = '';
        for (final element in subtitleList) {
          // ignore: use_string_buffers
          subtitle += element['text'].toString();
          if (element['text'].trim() == '•') {
            count++;
          } else {
            if (count == 0) {
              type += element['text'].toString();
            } else if (count == 1) {
              if (type.trim() == 'Artist') {
                subscribers += element['text'].toString();
              } else {
                if (element['text'].toString().trim() == '&') {
                  artist += ', ';
                } else {
                  artist += element['text'].toString();
                }
              }
            } else if (count == 2) {
              final String tt = type.trim();
              if (tt == 'Song') {
                album += element['text'].toString();
              } else if (tt == 'Video') {
                views += element['text'].toString();
              } else if (tt == 'Album' || tt == 'Single' || tt == 'EP') {
                year += element['text'].toString();
              } else if (tt.toLowerCase().contains('playlist')) {
                countSongs += element['text'].toString();
              }
            } else if (count == 3) {
              duration += element['text'].toString();
            }
          }
        }
        final String tType = type.trim();
        final List idNav = (tType == 'Song' || tType == 'Video')
            ? ['playlistItemData', 'videoId']
            : ['navigationEndpoint', 'browseEndpoint', 'browseId'];
        final String id = nav(renderer, idNav)?.toString() ?? '';
        if (id.isEmpty && title.isEmpty) {
          return null;
        }
        return {
          'id': id,
          'type': tType,
          'title': title,
          'artist': tType == 'Artist' ? title : artist,
          'album': album,
          'duration': duration,
          'views': views,
          'year': year,
          'countSongs': countSongs,
          'subtitle': subtitle,
          'image': images.isNotEmpty ? images.first : '',
          'images': images,
          'subscribers': subscribers,
        };
      }

      final Map<String, List> groupedResults = {};
      for (final sectionItem in finalResults) {
        // New format: itemSectionRenderer (one result each).
        // Old format: musicShelfRenderer with grouped contents.
        final List childItems =
            (nav(sectionItem, ['itemSectionRenderer', 'contents'])
                    as List?) ??
                (nav(sectionItem, ['musicShelfRenderer', 'contents'])
                    as List?) ??
                [];
        for (final childItem in childItems) {
          final parsed = parseItem(childItem);
          if (parsed == null) {
            continue;
          }
          final String section = sectionForType(parsed['type'] as String);
          (groupedResults[section] ??= []).add(parsed);
        }
      }

      const List<String> sectionOrder = [
        'Songs',
        'Videos',
        'Albums',
        'Artists',
        'Playlists',
      ];
      final List<String> orderedKeys = [
        ...sectionOrder.where((k) => groupedResults.containsKey(k)),
        ...groupedResults.keys.where((k) => !sectionOrder.contains(k)),
      ];
      for (final key in orderedKeys) {
        final List items = groupedResults[key] ?? [];
        if (items.isNotEmpty) {
          searchResults.add({'title': key, 'items': items});
        }
      }
      return searchResults;
    } catch (e) {
      Logger.root.severe('Error in yt search', e);
      return List.empty();
    }
  }

  Future<List<String>> getSearchSuggestions({
    required String query,
    String? scope,
    bool ignoreSpelling = false,
    String? filter = 'songs',
  }) async {
    if (headers == null) {
      await init();
    }
    try {
      final body = Map.from(context!);
      body['input'] = query;
      final Map response =
          await sendRequest(endpoints['search_suggestions']!, body, headers);
      final List finalResult = nav(response, [
            'contents',
            0,
            'searchSuggestionsSectionRenderer',
            'contents'
          ]) as List? ??
          [];
      final List<String> results = [];
      for (final item in finalResult) {
        results.add(
          nav(item, [
            'searchSuggestionRenderer',
            'navigationEndpoint',
            'searchEndpoint',
            'query'
          ]).toString(),
        );
      }
      return results;
    } catch (e) {
      Logger.root.severe('Error in yt search suggestions', e);
      return List.empty();
    }
  }

  int getDatestamp() {
    final DateTime now = DateTime.now();
    final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final Duration difference = now.difference(epoch);
    final int days = difference.inDays;
    return days;
  }

  // Public entry point:
  //   1. Fetch metadata from InnerTube (title/artist/image — fast)
  //   2. ALWAYS resolve stream URL via youtube_explode_dart (handles n-param cipher)
  //   Merging the two gives reliable playback + accurate metadata.
  Future<Map> getSongData({required String videoId}) async {
    // Metadata pass (InnerTube — non-blocking if it fails)
    final Map metadata = await _getSongDataVR(videoId: videoId);

    // Stream URL pass — youtube_explode_dart decodes YouTube's n-param
    try {
      final yt = YoutubeExplode();
      try {
        final manifest = await yt
            .videos.streamsClient
            .getManifest(VideoId(videoId));
        final List<AudioOnlyStreamInfo> sorted =
            manifest.audioOnly.sortByBitrate();
        if (sorted.isEmpty) {
          yt.close();
          return metadata; // no streams from explode, use InnerTube URL as-is
        }
        // On Android, m4a (mp4a) is more reliably decoded by ExoPlayer.
        final List<AudioOnlyStreamInfo> m4a = sorted
            .where((s) => s.audioCodec.contains('mp4'))
            .toList();
        final List<AudioOnlyStreamInfo> chosen =
            m4a.isNotEmpty ? m4a : sorted;
        final String lowUrl = chosen.first.url.toString();
        final String highUrl = chosen.last.url.toString();
        final String ytQuality = Hive.box('settings')
            .get('ytQuality', defaultValue: 'Low')
            .toString();
        final String finalUrl = ytQuality == 'High' ? highUrl : lowUrl;
        final String expireAt =
            RegExp('expire=(.*?)&').firstMatch(finalUrl)?.group(1) ??
                ((DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600 * 5)
                    .toString();
        yt.close();
        try {
          await Hive.box('ytlinkcache').put(videoId, {
            'url': finalUrl,
            'expire_at': expireAt,
            'lowUrl': lowUrl,
            'highUrl': highUrl,
          });
        } catch (_) {}
        // Use InnerTube metadata if we got it, otherwise minimal map.
        final Map base = metadata.isNotEmpty
            ? metadata
            : {
                'id': videoId,
                'title': '',
                'artist': '',
                'album': '',
                'duration': '',
                'image': '',
                'images': <String>[],
                'language': 'YouTube',
                'genre': 'YouTube',
                'year': '',
                '320kbps': 'false',
                'has_lyrics': 'false',
                'release_date': '',
                'album_id': '',
                'subtitle': '',
                'perma_url': 'https://youtube.com/watch?v=$videoId',
              };
        return {
          ...base,
          'url': finalUrl,
          'lowUrl': lowUrl,
          'highUrl': highUrl,
          'expire_at': expireAt,
        };
      } catch (e) {
        yt.close();
        rethrow;
      }
    } catch (e) {
      Logger.root.severe('getSongData explode url failed for $videoId: $e');
      // Last resort: InnerTube URL (may 403 on some content)
      if (metadata.isNotEmpty) return metadata;
      final Map? fallback =
          await YouTubeServices().formatVideoFromId(id: videoId);
      return fallback ?? {};
    }
  }

  // Client priority order based on OuterTune + Metrolist + Bloom research:
  //   1. ANDROID_VR — OuterTune's "only currently working client" (direct URLs, no cipher)
  //   2. ANDROID   — Bloom primary (direct URLs; may need cipher on some content)
  //   3. IOS       — Bloom secondary (direct URLs)
  // youtube_explode_dart handles cipher for anything that falls through.
  Future<Map> _getSongDataVR({required String videoId}) async {
    Map result = await _playerRequest(
      videoId: videoId,
      clientName: 'ANDROID_VR',
      clientVersion: '1.56.21',
      clientNumericId: '28',
      userAgent:
          'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
    );
    if (result.isNotEmpty) return result;
    result = await _playerRequest(
      videoId: videoId,
      clientName: 'ANDROID',
      clientVersion: '21.26.364',
      clientNumericId: '3',
      userAgent:
          'com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip',
    );
    if (result.isNotEmpty) return result;
    return _playerRequest(
      videoId: videoId,
      clientName: 'IOS',
      clientVersion: '20.10.4',
      clientNumericId: '5',
      userAgent:
          'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 gzip',
    );
  }

  // Shared InnerTube /player request. Returns a song map on success, {} on
  // any failure (non-200, no direct URLs, exception).
  Future<Map> _playerRequest({
    required String videoId,
    required String clientName,
    required String clientVersion,
    required String clientNumericId,
    required String userAgent,
  }) async {
    try {
      if (headers == null) await init();
      final String visitorData = headers!['X-Goog-Visitor-Id'] ?? '';
      final Uri uri = Uri.https(
        'www.youtube.com',
        '/youtubei/v1/player',
        {'prettyPrint': 'false'},
      );
      final Map<String, dynamic> body = {
        'context': {
          'client': {
            'clientName': clientName,
            'clientVersion': clientVersion,
            'hl': 'en',
            'gl': 'US',
            if (visitorData.isNotEmpty) 'visitorData': visitorData,
          },
        },
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
      };
      final response = await post(
        uri,
        headers: {
          'content-type': 'application/json',
          'user-agent': userAgent,
          'X-YouTube-Client-Name': clientNumericId,
          'X-YouTube-Client-Version': clientVersion,
          if (visitorData.isNotEmpty) 'X-Goog-Visitor-Id': visitorData,
        },
        body: jsonEncode(body),
      );
      if (response.statusCode != 200) {
        Logger.root.severe(
            '_playerRequest $clientName returned ${response.statusCode}');
        return {};
      }
      final Map data = json.decode(response.body) as Map;
      final String playability =
          nav(data, ['playabilityStatus', 'status'])?.toString() ?? '';
      final List formats = [
        ...(nav(data, ['streamingData', 'adaptiveFormats']) as List? ?? []),
        ...(nav(data, ['streamingData', 'formats']) as List? ?? []),
      ];
      final List audioFormats = formats
          .where(
            (e) =>
                e['url'] != null &&
                e['bitrate'] != null &&
                e['mimeType'].toString().startsWith('audio'),
          )
          .toList();
      if (audioFormats.isEmpty) {
        Logger.root.severe(
            '_playerRequest $clientName: no direct url (status: $playability)');
        return {};
      }
      audioFormats.sort(
        (a, b) => int.parse(a['bitrate'].toString())
            .compareTo(int.parse(b['bitrate'].toString())),
      );
      final String lowUrl = audioFormats.first['url'].toString();
      final String highUrl = audioFormats.last['url'].toString();
      final String ytQuality =
          Hive.box('settings').get('ytQuality', defaultValue: 'Low').toString();
      final String finalUrl = ytQuality == 'High' ? highUrl : lowUrl;
      final String expireAt =
          RegExp('expire=(.*?)&').firstMatch(finalUrl)?.group(1) ??
              ((DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600 * 5)
                  .toString();
      final Map videoDetails = (nav(data, ['videoDetails']) as Map?) ?? {};
      final List thumbs =
          (nav(videoDetails, ['thumbnail', 'thumbnails']) as List?) ?? [];
      final String image =
          thumbs.isNotEmpty ? thumbs.last['url'].toString() : '';
      try {
        await Hive.box('ytlinkcache').put(videoId, {
          'url': finalUrl,
          'expire_at': expireAt,
          'lowUrl': lowUrl,
          'highUrl': highUrl,
        });
      } catch (_) {}
      return {
        'id': videoDetails['videoId'] ?? videoId,
        'title': videoDetails['title'] ?? '',
        'artist': (videoDetails['author'] ?? '')
            .toString()
            .replaceAll('- Topic', '')
            .trim(),
        'album': '',
        'duration': videoDetails['lengthSeconds']?.toString(),
        'url': finalUrl,
        'lowUrl': lowUrl,
        'highUrl': highUrl,
        'expire_at': expireAt,
        'image': image,
        'images': thumbs.map((e) => e['url']).toList(),
        'language': 'YouTube',
        'genre': 'YouTube',
        'year': '',
        '320kbps': 'false',
        'has_lyrics': 'false',
        'release_date': '',
        'album_id': videoDetails['channelId'] ?? '',
        'subtitle': videoDetails['author'] ?? '',
        'perma_url': 'https://youtube.com/watch?v=$videoId',
        'views': videoDetails['viewCount'],
      };
    } catch (e) {
      Logger.root.severe('_playerRequest $clientName error for $videoId', e);
      return {};
    }
  }

  Future<Map> getPlaylistDetails(String playlistId) async {
    if (headers == null) {
      await init();
    }
    try {
      final browseId =
          playlistId.startsWith('VL') ? playlistId : 'VL$playlistId';
      final body = Map.from(context!);
      body['browseId'] = browseId;
      final Map response =
          await sendRequest(endpoints['browse']!, body, headers);

      // Header — YTM uses different renderer types across playlist kinds.
      dynamic _h(List path) {
        for (final hKey in [
          'musicDetailHeaderRenderer',
          'musicEditablePlaylistDetailHeaderRenderer',
          'musicImmersiveHeaderRenderer',
          'musicResponsiveHeaderRenderer', // standard albums (OuterTune/Metrolist)
        ]) {
          final v = nav(response, ['header', hKey, ...path]);
          if (v != null) return v;
        }
        return null;
      }

      final String? heading =
          _h(['title', 'runs', 0, 'text']) as String?;
      final String subtitle =
          (_h(['subtitle', 'runs']) as List? ?? [])
              .map((e) => e['text'])
              .join();
      final String? description =
          _h(['description', 'runs', 0, 'text']) as String?;
      // Try croppedSquare first (older), fall back to musicThumbnailRenderer.
      final List rawThumbs = (_h([
                'thumbnail',
                'croppedSquareThumbnailRenderer',
                'thumbnail',
                'thumbnails'
              ]) ??
              _h(['thumbnail', 'musicThumbnailRenderer', 'thumbnail',
                  'thumbnails']) ??
              []) as List? ??
          [];
      final List images = rawThumbs.map((e) => e['url']).toList();

      // Content — try singleColumn then twoColumn layout.
      List finalResults = nav(response, [
            'contents',
            'singleColumnBrowseResultsRenderer',
            'tabs',
            0,
            'tabRenderer',
            'content',
            'sectionListRenderer',
            'contents',
            0,
            'musicPlaylistShelfRenderer',
            'contents'
          ]) as List? ??
          nav(response, [
            'contents',
            'twoColumnBrowseResultsRenderer',
            'secondaryContents',
            'sectionListRenderer',
            'contents',
            0,
            'musicPlaylistShelfRenderer',
            'contents'
          ]) as List? ??
          [];

      final List<Map> songResults = [];
      for (final item in finalResults) {
        try {
          final String id = nav(item, [
                'musicResponsiveListItemRenderer',
                'playlistItemData',
                'videoId'
              ])?.toString() ??
              '';
          if (id.isEmpty || id == 'null') continue;
          final String image = nav(item, [
                'musicResponsiveListItemRenderer',
                'thumbnail',
                'musicThumbnailRenderer',
                'thumbnail',
                'thumbnails',
                0,
                'url'
              ])?.toString() ??
              '';
          final String title = nav(item, [
                'musicResponsiveListItemRenderer',
                'flexColumns',
                0,
                'musicResponsiveListItemFlexColumnRenderer',
                'text',
                'runs',
                0,
                'text'
              ])?.toString() ??
              '';
          final List subtitleList = nav(item, [
                'musicResponsiveListItemRenderer',
                'flexColumns',
                1,
                'musicResponsiveListItemFlexColumnRenderer',
                'text',
                'runs'
              ]) as List? ??
              [];
          int count = 0;
          String year = '';
          String album = '';
          String artist = '';
          String albumArtist = '';
          String duration = '';
          String subtitle = '';
          for (final element in subtitleList) {
            subtitle += element['text'].toString();
            if (element['text'].trim() == '•') {
              count++;
            } else {
              if (count == 0) {
                if (element['text'].toString().trim() == '&') {
                  artist += ', ';
                } else {
                  artist += element['text'].toString();
                  if (albumArtist.isEmpty) albumArtist = artist;
                }
              } else if (count == 1) {
                album += element['text'].toString();
              } else if (count == 2) {
                duration += element['text'].toString();
              }
            }
          }
          songResults.add({
            'id': id,
            'type': 'song',
            'title': title,
            'artist': artist,
            'genre': 'YouTube',
            'language': 'YouTube',
            'year': year,
            'album_artist': albumArtist,
            'album': album,
            'duration': duration,
            'subtitle': subtitle,
            'image': image,
            'perma_url': 'https://www.youtube.com/watch?v=$id',
            'url': 'https://www.youtube.com/watch?v=$id',
            'release_date': '',
            'album_id': '',
            'expire_at': '0',
          });
        } catch (e) {
          Logger.root.warning('getPlaylistDetails: skipping malformed item', e);
        }
      }
      return {
        'songs': songResults,
        'name': heading,
        'subtitle': subtitle,
        'description': description,
        'images': images,
        'id': playlistId,
        'type': 'playlist',
      };
    } catch (e) {
      Logger.root.severe('Error in ytmusic getPlaylistDetails', e);
      return {};
    }
  }

  Future<Map> getAlbumDetails(String albumId) async {
    if (headers == null) {
      await init();
    }
    try {
      final body = Map.from(context!);
      body['browseId'] = albumId;
      final Map response =
          await sendRequest(endpoints['browse']!, body, headers);
      // Try multiple header renderer types (standard albums use musicResponsiveHeaderRenderer).
      dynamic ah(List path) {
        for (final hKey in [
          'musicDetailHeaderRenderer',
          'musicImmersiveHeaderRenderer',
          'musicResponsiveHeaderRenderer',
        ]) {
          final v = nav(response, ['header', hKey, ...path]);
          if (v != null) return v;
        }
        return null;
      }

      final String? heading = ah([...titleText]) as String?;
      final String subtitle = joinRunTexts(
        ah([...subtitleRuns]) as List? ?? [],
      );
      final String description = joinRunTexts(
        ah([...secondSubtitleRuns]) as List? ?? [],
      );
      final List images = runUrls(
        (ah([...thumbnailCropped]) ??
                ah(['thumbnail', 'musicThumbnailRenderer', ...thumbnail])) as List? ??
            [],
      );
      final List finalResults = nav(response, [
            ...singleColumnTab,
            ...sectionListItem,
            ...musicShelf,
            'contents',
          ]) as List? ??
          [];
      final List<Map> songResults = [];
      for (final item in finalResults) {
        final String id = nav(item, mrlirPlaylistId).toString();
        final String image = nav(item, [
          mRLIR,
          ...thumbnails,
          0,
          'url',
        ]).toString();
        final String title = nav(item, [
          mRLIR,
          'flexColumns',
          0,
          mRLIFCR,
          ...textRunText,
        ]).toString();
        final List subtitleList = nav(item, [
              mRLIR,
              'flexColumns',
              1,
              mRLIFCR,
              ...textRuns,
            ]) as List? ??
            [];
        int count = 0;
        String year = '';
        String album = '';
        String artist = '';
        String albumArtist = '';
        String duration = '';
        String subtitle = '';
        year = '';
        for (final element in subtitleList) {
          // ignore: use_string_buffers
          subtitle += element['text'].toString();
          if (element['text'].trim() == '•') {
            count++;
          } else {
            if (count == 0) {
              if (element['text'].toString().trim() == '&') {
                artist += ', ';
              } else {
                artist += element['text'].toString();
                if (albumArtist == '') {
                  albumArtist = element['text'].toString();
                }
              }
            } else if (count == 1) {
              album += element['text'].toString();
            } else if (count == 2) {
              duration += element['text'].toString();
            }
          }
        }
        songResults.add({
          'id': id,
          'type': 'song',
          'title': title,
          'artist': artist,
          'genre': 'YouTube',
          'language': 'YouTube',
          'year': year,
          'album_artist': albumArtist,
          'album': album,
          'duration': duration,
          'subtitle': subtitle,
          'image': image,
          'perma_url': 'https://www.youtube.com/watch?v=$id',
          'url': 'https://www.youtube.com/watch?v=$id',
          'release_date': '',
          'album_id': '',
        });
      }
      return {
        'songs': songResults,
        'name': heading,
        'subtitle': subtitle,
        'description': description,
        'images': images,
        'id': albumId,
        'type': 'album',
      };
    } catch (e) {
      Logger.root.severe('Error in ytmusic getAlbumDetails', e);
      return {};
    }
  }

  Future<Map<String, dynamic>> getArtistDetails(String id) async {
    if (headers == null) {
      await init();
    }
    String artistId = id;
    if (artistId.startsWith('MPLA')) {
      artistId = artistId.substring(4);
    }
    try {
      final body = Map.from(context!);
      body['browseId'] = artistId;
      final Map response =
          await sendRequest(endpoints['browse']!, body, headers);
      // final header = response['header']['musicImmersiveHeaderRenderer']
      final String? heading =
          nav(response, [...immersiveHeaderDetail, ...titleText]) as String?;
      final String subtitle = joinRunTexts(
        nav(response, [...immersiveHeaderDetail, ...subtitleRuns]) as List? ??
            [],
      );
      final String description = joinRunTexts(
        nav(response, [...immersiveHeaderDetail, ...secondSubtitleRuns])
                as List? ??
            [],
      );
      final List images = runUrls(
        nav(response, [...immersiveHeaderDetail, ...thumbnails]) as List? ?? [],
      );
      final List finalResults = nav(response, [
            ...singleColumnTab,
            ...sectionList,
            0,
            ...musicShelf,
            'contents',
          ]) as List? ??
          [];
      final List<Map> songResults = [];
      for (final item in finalResults) {
        final String id = nav(item, mrlirPlaylistId).toString();
        final String image = nav(item, [
          mRLIR,
          ...thumbnails,
          0,
          'url',
        ]).toString();
        final String title = nav(item, [
          mRLIR,
          'flexColumns',
          0,
          mRLIFCR,
          ...textRunText,
        ]).toString();
        final List subtitleList = nav(item, [
              mRLIR,
              'flexColumns',
              1,
              mRLIFCR,
              ...textRuns,
            ]) as List? ??
            [];
        int count = 0;
        String year = '';
        String album = '';
        String artist = '';
        String albumArtist = '';
        String duration = '';
        String subtitle = '';
        year = '';
        for (final element in subtitleList) {
          // ignore: use_string_buffers
          subtitle += element['text'].toString();
          if (element['text'].trim() == '•') {
            count++;
          } else {
            if (count == 0) {
              if (element['text'].toString().trim() == '&') {
                artist += ', ';
              } else {
                artist += element['text'].toString();
                if (albumArtist == '') {
                  albumArtist = element['text'].toString();
                }
              }
            } else if (count == 1) {
              album += element['text'].toString();
            } else if (count == 2) {
              duration += element['text'].toString();
            }
          }
        }
        songResults.add({
          'id': id,
          'type': 'song',
          'title': title,
          'artist': artist,
          'genre': 'YouTube',
          'language': 'YouTube',
          'year': year,
          'album_artist': albumArtist,
          'album': album,
          'duration': duration,
          'subtitle': subtitle,
          'image': image,
          'perma_url': 'https://www.youtube.com/watch?v=$id',
          'url': 'https://www.youtube.com/watch?v=$id',
          'release_date': '',
          'album_id': '',
        });
      }
      return {
        'songs': songResults,
        'name': heading,
        'subtitle': subtitle,
        'description': description,
        'images': images,
        'id': artistId,
        'type': 'artist',
      };
    } catch (e) {
      Logger.root.info('Error in ytmusic getArtistDetails', e);
      return {};
    }
  }

  Future<List<String>> getWatchPlaylist({
    String? videoId,
    String? playlistId,
    int limit = 25,
    bool radio = false,
    bool shuffle = false,
  }) async {
    if (headers == null) {
      await init();
    }
    try {
      final body = Map.from(context!);
      body['enablePersistentPlaylistPanel'] = true;
      body['isAudioOnly'] = true;
      body['tunerSettingValue'] = 'AUTOMIX_SETTING_NORMAL';

      if (videoId == null && playlistId == null) {
        return [];
      }
      if (videoId != null) {
        body['videoId'] = videoId;
        playlistId ??= 'RDAMVM$videoId';
        if (!(radio || shuffle)) {
          body['watchEndpointMusicSupportedConfigs'] = {
            'watchEndpointMusicConfig': {
              'hasPersistentPlaylistPanel': true,
              'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV;',
            }
          };
        }
      }
      // bool is_playlist = false;

      body['playlistId'] = playlistIdTrimmer(playlistId!);
      // is_playlist = body['playlistId'].toString().startsWith('PL') ||
      //     body['playlistId'].toString().startsWith('OLA');

      if (shuffle) body['params'] = 'wAEB8gECKAE%3D';
      if (radio) body['params'] = 'wAEB';
      final Map response = await sendRequest(endpoints['next']!, body, headers);
      final Map results = nav(response, [
            'contents',
            'singleColumnMusicWatchNextResultsRenderer',
            'tabbedRenderer',
            'watchNextTabbedResultsRenderer',
            'tabs',
            0,
            'tabRenderer',
            'content',
            'musicQueueRenderer',
            'content',
            'playlistPanelRenderer',
          ]) as Map? ??
          {};
      final playlist = (results['contents'] as List<dynamic>).where(
        (x) =>
            nav(x, ['playlistPanelVideoRenderer', ...navigationPlaylistId]) !=
            null,
      );
      int count = 0;
      final List<String> songResults = [];
      for (final item in playlist) {
        if (count > 0) {
          final String id =
              nav(item, ['playlistPanelVideoRenderer', 'videoId']).toString();
          songResults.add(id);
        } else {
          count++;
        }
      }
      return songResults;
    } catch (e) {
      Logger.root.severe('Error in ytmusic getWatchPlaylist', e);
      return [];
    }
  }
}
