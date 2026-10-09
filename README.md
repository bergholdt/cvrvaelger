# Cvrvaelger

Ruby client for **Det Centrale Virksomhedsregister (CVR)** via
[Datafordeler GraphQL](https://datafordeler.dk/dataoversigt/det-centrale-virksomhedsregister-cvr/cvr-graphql/).
Denmark only — verify an 8-digit CVR and return the registered company name
(plus light address fields for picker UX).

## Install

```ruby
# Gemfile
gem "cvrvaelger"
```

```sh
bundle add cvrvaelger
```

Requires Ruby 3.3+. No Rails dependency.

## Usage

```ruby
require "cvrvaelger"

client = Cvrvaelger::Client.new(
  api_key: ENV.fetch("CVRVAELGER_API_KEY")
)

company = client.lookup("47458714")
company.cvr  # => "47458714"
company.name # => "LEGO SYSTEM A/S"

# Picker: 8 digits → lookup; otherwise exact, case-sensitive name match.
# Datafordeler string filters are `eq` / `in` only (no contains).
hits = client.search("LEGO SYSTEM A/S")
client.search("lego") # => []
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
```

Unit tests inject a fake HTTP callable. Live examples are recorded with VCR
(`test/cassettes`) and replayed in CI without an API key. Re-record locally
with `CVRVAELGER_API_KEY` set and `VCR_RECORD=all`. Cassettes store the key as
`<API_KEY>`.

## Scope

**In:** Datafordeler CVR GraphQL v2 lookup/search, company name + light address.

**Out:** Rails controllers/Stimulus, CRM sync, person data (`CVRPerson`),
billing/credit scores, UK Companies House (host-app adapter later).

## Attribution

Company data via [Datafordeler](https://datafordeler.dk/) / Erhvervsstyrelsen CVR.
This gem is an independent open-source client and is not affiliated with or
endorsed by those agencies.

## Releasing

Same Trusted Publishing flow as `adressevaelger`:

1. Bump `Cvrvaelger::VERSION` and `CHANGELOG.md`.
2. Tag `vX.Y.Z` matching the version.
3. `push_gem.yml` publishes via OIDC (pending trusted publisher on RubyGems).

## License

MIT. See [LICENSE.txt](LICENSE.txt).
