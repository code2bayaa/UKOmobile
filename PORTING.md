# UKO mobile: Expo/React Native to Flutter port

This directory is a Flutter rewrite of `../mobile` (Expo Router, RN 0.81). The Expo app is unchanged, so the two can be compared side by side.
The Android application id is `ke.co.uko.uko_movies` (renamed 2026-09-29 from the Expo template's `com.expostarter.base`, which `mobile/app.config.ts` still uses), so this APK installs alongside the Expo build instead of replacing it. `minSdk` is 26, the same as expo-build-properties.

## How to run

```powershell
# Windows PowerShell
.\run_dev.ps1                       # flutter run
.\run_dev.ps1 build apk --debug     # flutter build apk --debug
.\run_dev.ps1 -EnvFile C:\path\.env run -d <device>
```
```bash
# Git Bash / macOS / Linux
./run_dev.sh
./run_dev.sh build apk --debug
ENV_FILE=/path/.env ./run_dev.sh run -d <device>
```

The scripts read `../mobile/.env`, strip the `EXPO_PUBLIC_` prefix, and pass the values as dart-defines. `lib/core/env.dart` reads them with `String.fromEnvironment`. Rules:
- **Values are never in source.** `env.dart` holds only variable names, and the defines go through a temporary JSON file in the system temp dir (`--dart-define-from-file`) that is deleted afterwards.
- **`*_SECRET` variables are always skipped.** A secret must never be compiled into a client. The current `.env` has none; if `RECAPTCHA_SITE_SECRET` or similar is added, it will not be passed.
- **Only names declared in `env.dart` are passed.** That file is pruned to the variables the Dart code actually uses.
- **Only one half is passed, chosen by `ENVIRONMENT`.** For `development` the plain names are passed; otherwise the `*_LIVE` names. At runtime `Env.isDev` / `Api.*` pick the same half, just like RN's `ENVIRONMENT === "development" ? X : X_LIVE`.
- **Why the filtering is needed:** Flutter forwards every define to `gradlew.bat` on the command line. All 157 entries go past cmd.exe's 8191-character limit and the Gradle step fails with "The command line is too long."

A plain `flutter run` with no defines still builds, but every endpoint is empty.

## Architecture (RN to Dart)

| RN | Dart |
|---|---|
| `app/_layout.tsx` (providers, theme, root Stack), `SOCKETS.connect()` | `lib/main.dart`, `lib/routes.dart` (`onGenerateRoute`, route names are the expo paths) |
| `app/(tabs)/_layout.tsx`, `components/home/tablayout.tsx` | `lib/shell/tab_shell.dart`: header with the menu icon, bottom tabs, and the centre "remote ON/OFF" button (`movies/action.tsx`) |
| `components/home/drawer.tsx` | `lib/shell/app_drawer.dart` |
| `components/home/safe.tsx` (KeyProvider/useKeys) | `lib/services/keys.dart`: `KeyService`. Screens can `await ready` before building TMDB URLs. |
| `components/home/remote.tsx` + every `SOCKETS.socketModule.emit` | `lib/services/remote.dart`: `RemoteService` and `TvPaths` |
| `middleware/sockets.js` | `lib/services/sockets.dart` |
| `graphQL/apollo.ts`, `provider.tsx`, `lib/safeLazyQuery.ts` | `lib/services/graphql.dart`: `Gql.query` / `Gql.mutate` return `null` on any error |
| AsyncStorage | `lib/services/prefs.dart`: shared_preferences with the same key names (`user`, `remote`, `location`, `device`, `type`) |
| `lib/safeJson.ts`, `fetch` | `lib/core/http.dart` |
| crypto-js SHA256, JS string concatenation | `lib/core/util.dart` (`sha256Hex`, `js()`, which matches JS stringification so the `hashedKey` strings are byte-identical) |
| `lib/constants.ts`, tailwind colours | `lib/core/theme.dart` |
| `middleware/report.js` (COLLECT) | `lib/services_ext/report.dart`: called on auto-login, same as `index.tsx` |
| `middleware/fileSystem.js` | `lib/screens/offline/file_system.dart`: same `video-store/{videos,subtitles,images}/index.json` layout |
| `components/home/picture.tsx` | `lib/widgets/picture.dart` |
| `components/home/pages.jsx` (SWEETPAGE) | `lib/widgets/sweet_page.dart` |
| `components/home/CategoryCard.tsx` | `lib/widgets/category_card.dart` |
| `components/home/celebraties.jsx` (+ reanimated-carousel) | `lib/widgets/celebraties.dart` (carousel_slider) |
| `components/home/MovieCard.tsx`, the inline `renderMovie` cards | `lib/widgets/common.dart` (`MediaCard`, `MediaRow`, `SectionHeader`, `ClickTvButton`, `LoadingView`, alerts) |
| `components/primitives/*`, `components/ui/*` | Not ported; Material widgets are used instead |

## Screens

| RN (`mobile/app/...`) | Dart (`lib/screens/...`) |
|---|---|
| `index.tsx` (sign-in, uko.mp4 background) | `auth/sign_in.dart` (+ `auth/account_form.dart`, `auth/form_field.dart` from `components/home/FormField.tsx`) |
| `signup.tsx` | `auth/signup.dart` |
| `change.tsx` | `auth/change.dart` |
| `+not-found.tsx` | `not_found.dart` |
| `(tabs)/home.tsx` + `components/home/{blockbuster,box,clips,clip}.jsx` | `home/home.dart`, `home/blockbuster.dart`, `home/box.dart`, `home/clips.dart`, `home/clip.dart`, `home/trailer_swiper.dart` |
| `(tabs)/movies/page.tsx` **and** `(tabs)/tv/page.tsx` | `browse/browse.dart` (`BrowseScreen(kind:)`) |
| `(tabs)/movies/id.tsx` | `movies/id.dart` (+ `movies/detail_common.dart`, shared with tv/id) |
| `(tabs)/tv/id.tsx` | `tv/id.dart` |
| `(tabs)/tv/season.tsx` | `tv/season.dart` (+ `tv/season_episode_parts.dart`) |
| `(tabs)/tv/episode.tsx` | `tv/episode.dart` |
| `(tabs)/{movies,tv}/{similar,recommendation}.tsx` (4 files) | `shared/related.dart` (`RelatedScreen(kind:, mode:)`) |
| `(tabs)/{movies,tv}/discover.tsx` + `components/home/controllers.jsx` | `shared/discover.dart`, `shared/controllers.dart` |
| `(tabs)/{movies,tv}/trailer.tsx` | `shared/trailer.dart` |
| `(tabs)/movies/action.tsx` (empty screen, tab button only) | the remote button in `shell/tab_shell.dart` |
| `(tabs)/screens/{anime,china,disney,hindu,korean,netflix}.tsx` + `components/home/latest.jsx` | `platform/platform.dart` (`PlatformScreen(platform:)` with a per-platform config table), `platform/latest.dart` |
| `(tabs)/people/page.tsx` | `people/page.dart` |
| `(tabs)/people/id.tsx` | `people/id.dart` |
| `(tabs)/search.tsx` | `user/search.dart` |
| `(tabs)/following.tsx` | `user/following.dart` |
| `(tabs)/playlist.tsx` | `user/playlist.dart` |
| `(tabs)/tvLogin.tsx` | `user/tv_login.dart` |
| `(tabs)/credits/buy.tsx` | `credits/buy.dart` |
| `(tabs)/credits/earn.tsx` | `credits/earn.dart` |
| `video/stream.tsx` + `components/home/collection.jsx` | `video/stream.dart`, `video/collection.dart` |
| `video/vlc.tsx` | `video/vlc.dart` (+ `video/player_shared.dart`) |
| `video/play.tsx` | `video/play.dart` |
| `video/speed.tsx` | `video/speed.dart` (media_kit) |
| `offline/downloads.tsx`, `offline/play.tsx` | `offline/downloads.dart`, `offline/play.dart` (+ `offline/player_time.dart`) |

## Phone-as-TV-remote protocol (`RemoteService`)

Every screen calls `RemoteService.instance.route(TvPaths.x, {'id': id, ...})`. It does nothing unless shared_preferences `remote == "on"`. Otherwise it connects the socket and emits:

- `("Route", userId, legacyName, tvPath, state)`. `tvPath` is checked against the TV app's route table (`TvPaths.all`). `state.id` is always an int.
- `PLAY` / `SLIDE` / `SUBTITLE` / `MUTE` as `(event, userId, value)`, where the value is the **new** state (PLAY `true` = play).
- `("tv-login", code, email)` from the TV Login screen.
- `("remote", userId)` after sign-in and again on every socket (re)connect.

Because the phone now joins its own room, the relay echoes the phone's own PLAY/SLIDE back to it. `onPlayerEvent` drops echoes of a value the phone sent in the last 1.5 s.

`/third` and `/remote` (the TV's VLC and remote players, opened from video/stream's "Choose player" dialog) are real TV routes but are not in the browsing list. They are allowed as `TvPaths.third` / `TvPaths.remotePlayer`.

## Behaves differently from RN

- **Navigation.** In-app navigation uses `Navigator.push`, so the back button returns to the previous screen. RN's movies/tv pages used `router.replace`. A bottom-tab tap resets the stack to Home plus that tab, like expo Tabs' "firstRoute" back behaviour.
- **TMDB keys.** Screens wait for the KEYS response before calling TMDB. In RN they raced it and could request `undefined?api_key=undefined`.
- **PayPal / M-PESA.** `credits/buy.tsx` is only a WebView on `${HOST}/subscribe/<user>`; its native payment code is all commented out. The port is the same WebView, and the payment flows stay on the web page.
- **Home and trailer swiper.** YouTube trailers autoplay only because they are muted. Some videos refuse to play embedded, and then auto-advance stops on them. A vertical swipe that starts on the video goes to the player, not the swiper.
- **Blur-until-loaded.** Picture's blur effect is replaced by a fade-in.
- **Unused RN code not ported.** `components/home/{popstar,carousel,countries,video,dash,load,bar,Icons,ThemeToggle}`, `components/habit/*` and `components/settings/*` are never rendered by any screen; `load.jsx` and `dash.jsx` are web-only. `carousel.jsx` is used only by the unused `popstar.jsx`, so its role is covered by carousel_slider in `celebraties.dart`. `lib/backHandlerShim.ts`, `hooks/useFrameworkReady.ts` and `lib/storage.ts` are RN/web-only.
- **Launcher icon.** It is copied from `mobile/android` (adaptive icon on a white background).

## RN bugs found (fixed in the port unless noted)

1. **Remote routes sent screen names instead of TV paths.** `search.tsx:257-261`, `playlist.tsx:210-212`, `following.tsx:278`, `components/home/celebraties.jsx:36`, `video/speed.tsx:820-822`, `video/vlc.tsx:854-856` sent names like "PeopleDetail", "TvDetail", "MovieDetail", "Episode" and "Season".
2. **Wrong TV paths.** `movies/page.tsx:691` sent `"/movies/top"`, which should be `/movies/rated`. `tv/page.tsx:615` sent Disney to `"/tv/netflix"`.
3. **Platform screens used the wrong route name.** `screens/*.tsx:~590` always sent "PeopleDetail" as the route name.
4. **"hindu" studio broken.** It never reached the TV, because `movies/page.tsx:678` compares against "hindi". Its card also fell back to the China image, because `CategoryCard.tsx` is keyed "hindi".
5. **TV-tab studio taps never mirrored.** `tv/page.tsx` never passed the studio title, so studio taps on the TV tab did not reach the TV.
6. **TV paging collided with movie paging.** `tv/page.tsx:284/344/367` hashed and typed TV pages as "movie", so TV "popular"/"trending" page N shared a cache key with the movie lists. TV now uses "tv". This changes those cache keys.
7. **Wrong mutation result keys.** `movies/page.tsx:101` and `tv/page.tsx:91` read `data.addMovies` in the `addCollectionMovies` handler. `clips.jsx:461/400/468` had the same problem (logging only).
8. **Player remote sent stale values.** `speed.tsx:579-604` and `vlc.tsx:629-655` emitted the pre-toggle state. PLAY happened to work because `play` means "paused"; SUBTITLE and MUTE reached the TV inverted.
9. **Socket listeners piled up.** `speed.tsx:1070` registered PLAY/SLIDE listeners on every render. `tvLogin.tsx:51` added a new "feedback-user-login" listener on every press.
10. **Undefined env vars.** `controllers.jsx:487-708`, `latest.jsx:149`, `trailer.tsx:121` and `similar.tsx:368` used `EXPO_PUBLIC_MOVIE_DB`, `EXPO_PUBLIC_API_KEY` and `EXPO_PUBLIC_IMG_POSTER`, none of which is in `.env`. As a result the discover filter lists never loaded. The port uses the KEYS values.
11. **Trailer swiper never had data.** `home.tsx:137` and `trailer.tsx:50` read `{node, movie}`, but clips sends `{key, movieInfo}`, so the swiper had no video id or details. Also, `handleNext` never scrolled, and `VideoItem` was redefined on every render.
12. **TV trailers could show a movie's details.** `clips.jsx:293` looked up TV details in the movie table by numeric id.
13. **Recommended TV opened the movie screen.** `tv/recommendation.tsx` pushed `/movies/id` for TV results.
14. **Movie detail cache never hit.** `movies/id.tsx` queried the image payload with type "tv" but inserted it as "movie".
15. **`collection.jsx:262` index encoding (kept as-is).** It replaces only the first occurrence of each digit (`"11"` becomes `"b1"`). This is kept exactly, because the server decodes that form.

## Verification status

- `flutter analyze` finds no issues.
- `flutter build apk --debug` (through `run_dev.ps1`) succeeds.
- Nothing has been run on a device or emulator; none was attached.
