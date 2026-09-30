/// movie vs tv — used to collapse the RN screens that exist once per kind
/// (movies/similar + tv/similar, movies/discover + tv/discover, ...).
enum MediaKind {
  movie,
  tv;

  bool get isTv => this == MediaKind.tv;

  /// TMDB path segment / GraphQL `type` value: "movie" | "tv"
  String get api => isTv ? 'tv' : 'movie';
}
