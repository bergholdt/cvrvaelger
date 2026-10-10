# frozen_string_literal: true

require_relative "cvrvaelger/version"
require_relative "cvrvaelger/error"
require_relative "cvrvaelger/company"
require_relative "cvrvaelger/file_download"
require_relative "cvrvaelger/client"

# Ruby client for Det Centrale Virksomhedsregister (CVR) via Datafordeler
# GraphQL and Fildownload.
#
# Denmark only. Rails controllers, Stimulus pickers, and persistence belong in the
# host application (same split as adressevaelger).
module Cvrvaelger
end
