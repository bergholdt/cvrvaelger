# Changelog

## Unreleased

## 0.2.0

- Fildownload client: `available_file_downloads`, `download_file`, `download_latest`
  for CVR totalextract zips.
- CVR_Events pull/poll: `events` (cursor via `since_event_id` / `after`),
  `virksomhed_by_row_id` / `navn_by_row_id` / `adressering_by_row_id`, and
  `register_import_status` for incremental sync after a TotalDownload baseline.

## 0.1.0

- Initial public release: Datafordeler CVR GraphQL v2 client (`lookup` / `search`).
- Returns company name, light address fields, and status for an 8-digit CVR or
  exact registered name match. Optional `at:` sets GraphQL `virkningstid`.
- Requires a free Datafordeler API key (`CVRVAELGER_API_KEY`); no demo secret.
- VCR cassettes for LEGO, Salling Group, empty searches, and the public query
  surface (API keys redacted).
- RuboCop in CI (`bundle exec rake rubocop`).
