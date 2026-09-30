import 'package:flutter/foundation.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../core/env.dart';

/// Port of graphQL/apollo.ts. Endpoint = GRAPHQL (development) or GRAPHQL_LIVE.
///
/// The RN screens call Apollo `useLazyQuery(..., {fetchPolicy: 'cache-first'})`
/// wrapped by lib/safeLazyQuery.ts (abort -> null). [Gql.query] / [Gql.mutate]
/// reproduce that: they return the `data` map, or `null` on any error, so the
/// callers' `if (fetched && fetched.data) ... else freshFetch()` logic ports 1:1.
class Gql {
  Gql._();
  static GraphQLClient? _client;

  static GraphQLClient get client => _client ??= _build();

  static GraphQLClient _build() {
    final uri = Env.isDev ? Env.graphql : Env.graphqlLive;
    if (kDebugMode) debugPrint('GraphQL Endpoint: $uri');
    return GraphQLClient(
      link: HttpLink(uri.isEmpty ? 'http://127.0.0.1/graphql' : uri),
      cache: GraphQLCache(store: InMemoryStore()),
      defaultPolicies: DefaultPolicies(
        query: Policies(fetch: FetchPolicy.cacheFirst, error: ErrorPolicy.none),
        mutate: Policies(fetch: FetchPolicy.noCache, error: ErrorPolicy.none),
      ),
    );
  }

  /// Lazy-query equivalent. Returns `result.data` or null (network error,
  /// GraphQL error, abort...). Use `FetchPolicy.noCache` where the RN code used
  /// `fetchPolicy: 'no-cache'`.
  static Future<Map<String, dynamic>?> query(
    String document,
    Map<String, dynamic> variables, {
    FetchPolicy fetchPolicy = FetchPolicy.cacheFirst,
  }) async {
    try {
      final res = await client.query(QueryOptions(
        document: gql(document),
        variables: variables,
        fetchPolicy: fetchPolicy,
      ));
      if (res.hasException) {
        debugPrint('[GQL] query error: ${res.exception}');
        return null;
      }
      return res.data;
    } catch (e) {
      debugPrint('[GQL] query failed: $e');
      return null;
    }
  }

  /// `useMutation` equivalent (fire and forget is fine: callers may ignore the
  /// future just like the RN code ignored the promise).
  static Future<Map<String, dynamic>?> mutate(String document, Map<String, dynamic> variables) async {
    try {
      final res = await client.mutate(MutationOptions(
        document: gql(document),
        variables: variables,
        fetchPolicy: FetchPolicy.noCache,
      ));
      if (res.hasException) {
        debugPrint('[GQL] mutation error: ${res.exception}');
        return null;
      }
      return res.data;
    } catch (e) {
      debugPrint('[GQL] mutation failed: $e');
      return null;
    }
  }
}
