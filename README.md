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

company = client.lookup("25052943")
company.cvr  # => "25052943"
company.name # => registered name

# Picker: 8 digits → lookup; otherwise name contains search
hits = client.search("Magenta")
```

Environment variables:

| Variable | Purpose |
| --- | --- |
| `CVRVAELGER_API_KEY` | Datafordeler API key (preferred) |
| `DATAFORDELER_API_KEY` | Accepted alias |
| `CVRVAELGER_BASE_URL` | Override GraphQL endpoint (default `https://graphql.datafordeler.dk/CVR/v1`) |

## API key

There is **no demo/default secret**. Create a free user + IT-system API key in
[Datafordeler Administration](https://datafordeler.dk/). Company entities do not
require a special CVR access request; `CVRPerson` is out of scope for this gem.

## Testing

```sh
bundle exec rake test
```

Unit tests inject a fake HTTP callable. Optional VCR cassettes against the live
API can be recorded when `CVRVAELGER_API_KEY` is set locally (`VCR_RECORD=all`).
CI uses injected HTTP only (fail-closed; no invented keys).

## Scope

**In:** Datafordeler CVR GraphQL lookup/search, company name + light address.

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
