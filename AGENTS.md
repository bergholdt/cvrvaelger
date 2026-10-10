# Agent notes

Public README is for gem users. Keep maintainer checklists and rejected scope out of it.

## Scope

**In:** Datafordeler CVR GraphQL v2 `lookup` / `search`, and Fildownload list/download
of totalextract zips (metadata + stream to disk).

**Out:** Rails controllers/Stimulus, scheduling, unzip/ETL/search indexes, CRM sync,
person data (`CVRPerson`), billing/credit scores, UK Companies House.

## Security

CodeQL (`.github/workflows/codeql.yml`), Dependabot (`.github/dependabot.yml`), secret scanning, and security advisories (`.github/SECURITY.md`).

## Test

```sh
bundle exec rake test
bundle exec rake rubocop
# or: bundle exec rake
```

## VCR

Cassettes are recorded against the real Datafordeler CVR GraphQL API. Do not hand-write response bodies.

```sh
VCR_RECORD=all bundle exec rake test TEST=test/client_live_test.rb
VCR_RECORD=all bundle exec rake test TEST=test/graphql_features_test.rb
VCR_RECORD=all bundle exec rake test TEST=test/file_download_live_test.rb
```

Do not VCR-record full entity zip downloads (hundreds of MB).

CI uses `record: :none`. API keys are redacted on record (`<API_KEY>`).

## Release

1. Bump `Cvrvaelger::VERSION` in `lib/cvrvaelger/version.rb`.
2. Update `CHANGELOG.md`.
3. Tag `vX.Y.Z` matching that version and push the tag.

`.github/workflows/push_gem.yml` checks the tag and publishes with RubyGems Trusted Publishing.
