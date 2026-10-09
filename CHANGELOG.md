# Changelog

## Unreleased

- Point the client at Datafordeler CVR GraphQL v2. Name search is an exact `eq` match, and `lookup`/`search` accept `at:` for `virkningstid`.
- Record VCR cassettes for LEGO, Salling Group, empty searches, and the public query fields.

## 0.1.0

- Initial release: Datafordeler CVR GraphQL `lookup` / `search`.
- Returns company name (+ light address fields) for an 8-digit CVR.
- Requires a free Datafordeler API key (`CVRVAELGER_API_KEY`); no demo secret.
