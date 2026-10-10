# Cvrvaelger

Ruby client for **Det Centrale Virksomhedsregister (CVR)** via
[Datafordeler GraphQL](https://datafordeler.dk/dataoversigt/det-centrale-virksomhedsregister-cvr/cvr-graphql/)
and [Fildownload](https://datafordeler.dk/dataoversigt/det-centrale-virksomhedsregister-cvr/cvr-fildownload/).

Denmark only — look up an 8-digit CVR or registered company name and return
picker-shaped fields (name, light address, status). Also supports Datafordeler
CVR Fildownload (list/download totalextract zips) and `CVR_Events` pull/poll for
incremental sync.

## Install

```ruby
# Gemfile
gem "cvrvaelger"
```

```sh
bundle add cvrvaelger
# or: gem install cvrvaelger
```

Requires Ruby 3.3+. No Rails dependency.

## Usage

```ruby
require "cvrvaelger"

client = Cvrvaelger::Client.new(
  api_key: ENV.fetch("CVRVAELGER_API_KEY")
)

company = client.lookup("47458714")
company.cvr          # => "47458714"
company.name         # => "LEGO SYSTEM A/S"
company.address_line # => "Åstvej 1"
company.postal_code # => "7190"
company.city         # => "Billund"
company.status       # => "aktiv"

# Picker: 8 digits → lookup; otherwise exact, case-sensitive name match.
# Datafordeler string filters are `eq` / `in` only (no contains / fuzzy).
hits = client.search("LEGO SYSTEM A/S")
client.search("lego") # => []

# Optional bitemporal cut-off (GraphQL `virkningstid`, default: now)
client.lookup("47458714", at: Time.utc(2020, 1, 1))

# Fildownload: list metadata and stream a zip to disk
files = client.available_file_downloads(entity: "Navn", type_of_data: "Current", format: "json")
client.download_latest(entity: "Virksomhed", type: "current", format: "json", to: "tmp/virksomhed.zip")
client.download_file(files.first.file_name, to: "tmp/navn.zip")

# Incremental sync after a TotalDownload baseline (persist last event_id yourself).
# See Datafordeler transitions guide for entitetsbaserede hændelser.
status = client.register_import_status
page = client.events(since_event_id: last_id, first: 100)
page.events.each do |event|
  # from_failed_import marks duplicate catch-up events — handle in the host app.
  next if event.event_action == "d" # delete local row for event.object_datafordeler_row_id

  case event.entity_name
  when "Virksomhed"
    client.virksomhed_by_row_id(event.object_datafordeler_row_id) # => Hash or nil
  when "Navn"
    client.navn_by_row_id(event.object_datafordeler_row_id)
  when "Adressering"
    client.adressering_by_row_id(event.object_datafordeler_row_id)
  # other entities: query GraphQL yourself
  end
end
page = client.events(since_event_id: last_id, first: 100, after: page.end_cursor) if page.has_next_page
```

SSE / GraphQL subscriptions are not wrapped here; poll with `events` instead.

Environment variables:

| Variable | Purpose |
| --- | --- |
| `CVRVAELGER_API_KEY` | Datafordeler API key (preferred) |
| `DATAFORDELER_API_KEY` | Accepted alias |
| `CVRVAELGER_BASE_URL` | Override GraphQL endpoint (default `https://graphql.datafordeler.dk/CVR/v2`) |
| `CVRVAELGER_FILE_DOWNLOAD_BASE_URL` | Override Fildownload host (default `https://api.datafordeler.dk`) |

## API key

There is **no demo/default secret**. Create a free user + IT-system API key in
[Datafordeler Administration](https://datafordeler.dk/). Company entities do not
require a special CVR access request; `CVRPerson` is out of scope for this gem.

## Testing

```sh
bundle exec rake test
bundle exec rake rubocop
```

Unit tests stub HTTP via an injected callable. Live examples use
[VCR](https://github.com/vcr/vcr) cassettes recorded against the real API
(API keys redacted as `<API_KEY>`). CI uses `record: :none` (fail-closed).
To refresh cassettes locally:

```sh
VCR_RECORD=all bundle exec rake test TEST=test/client_live_test.rb
VCR_RECORD=all bundle exec rake test TEST=test/graphql_features_test.rb
VCR_RECORD=all bundle exec rake test TEST=test/file_download_live_test.rb
VCR_RECORD=all bundle exec rake test TEST=test/client_events_live_test.rb
```

Never hand-write cassette response bodies.

## Attribution

Company data via [Datafordeler](https://datafordeler.dk/) / Erhvervsstyrelsen CVR.
This gem is an independent open-source client and is not affiliated with or
endorsed by those agencies.

## Releasing

1. Bump `Cvrvaelger::VERSION` in `lib/cvrvaelger/version.rb` (gemspec reads it).
2. Update `CHANGELOG.md` for that version.
3. Commit and push to `main`.
4. Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`
   (or create a GitHub Release for `vX.Y.Z` — that also pushes the tag).
5. Tag **must** match the gem version (`v0.1.0` ↔ `0.1.0`). The
   [push_gem](.github/workflows/push_gem.yml) workflow verifies this, then
   publishes via [RubyGems Trusted Publishing](https://guides.rubygems.org/trusted-publishing/)
   (`rubygems/release-gem`, OIDC — no `RUBYGEMS_API_KEY` secret).

## License

MIT. See [LICENSE.txt](LICENSE.txt).
