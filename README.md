# Cvrvaelger

Ruby client for **Det Centrale Virksomhedsregister (CVR)** via
[Datafordeler GraphQL](https://datafordeler.dk/dataoversigt/det-centrale-virksomhedsregister-cvr/cvr-graphql/).

Denmark only — look up an 8-digit CVR or registered company name and return
picker-shaped fields (name, light address, status).

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
```

Environment variables:

| Variable | Purpose |
| --- | --- |
| `CVRVAELGER_API_KEY` | Datafordeler API key (preferred) |
| `DATAFORDELER_API_KEY` | Accepted alias |
| `CVRVAELGER_BASE_URL` | Override GraphQL endpoint (default `https://graphql.datafordeler.dk/CVR/v2`) |

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
