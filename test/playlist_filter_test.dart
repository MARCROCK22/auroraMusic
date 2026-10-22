import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/playlist_detail_tools.dart';

void main() {
  Track t(String id, String title, String artist) =>
      Track(id: id, title: title, artist: artist);
  final tracks = [
    t('1', 'Beta', 'Zed'),
    t('2', 'alfa', 'Amy'),
    t('3', 'Gamma', 'amy'),
  ];
  List<String> ids(List<Track> l) => [for (final x in l) x.id];

  test('search matches title or artist, case-insensitive', () {
    expect(ids(filterPlaylistTracks(tracks, query: 'ZED')), ['1']);
    expect(ids(filterPlaylistTracks(tracks, query: 'amy')), ['2', '3']);
  });
  test('artist filter ignores case', () {
    expect(ids(filterPlaylistTracks(tracks, artist: 'Amy')), ['2', '3']);
  });
  test('sorts', () {
    expect(ids(filterPlaylistTracks(tracks, sort: PlaylistSort.titleAsc)), [
      '2',
      '1',
      '3',
    ]);
    expect(ids(filterPlaylistTracks(tracks, sort: PlaylistSort.titleDesc)), [
      '3',
      '1',
      '2',
    ]);
    expect(ids(filterPlaylistTracks(tracks, sort: PlaylistSort.artist)), [
      '2',
      '3',
      '1',
    ]);
    expect(ids(filterPlaylistTracks(tracks, sort: PlaylistSort.recent)), [
      '3',
      '2',
      '1',
    ]);
  });
  test('artists distinct', () {
    expect(playlistArtists(tracks), ['Zed', 'Amy']);
  });
}
