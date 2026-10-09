# frozen_string_literal: true

module Cvrvaelger
  PROVIDER = "datafordeler_cvr"

  # Verified company hit from CVR (picker-shaped; no host-app persistence).
  Company = Data.define(
    :cvr,
    :name,
    :address_line,
    :postal_code,
    :city,
    :provider,
    :status
  ) do
    def self.from_node(node)
      cvr = normalize_cvr(node["cvrNummer"] || node["CVRNummer"] || node["cvr"])
      name = extract_name(node)
      address = node["adresse"] || node["beliggenhedsadresse"] || {}
      address = {} unless address.is_a?(Hash)

      new(
        cvr: cvr,
        name: name,
        address_line: build_address_line(address, node),
        postal_code: present_string(scalar(address["postnummer"] || address["postnr"] || node["postnummer"])),
        city: present_string(scalar(address["postdistrikt"] || address["postnummerNavn"] || node["bynavn"])),
        provider: PROVIDER,
        status: present_string(scalar(node["status"] || node["virksomhedsstatus"]))
      )
    end

    def self.normalize_cvr(value)
      digits = value.to_s.gsub(/\D/, "")
      digits.match?(/\A\d{8}\z/) ? digits : nil
    end

    def self.extract_name(node)
      raw = node["navn"] || node["navne"] || node["name"]
      case raw
      when String then present_string(raw)
      when Hash then present_string(scalar(raw["navn"] || raw["name"]))
      when Array
        first = raw.find { |row| row.is_a?(Hash) } || raw.first
        if first.is_a?(Hash)
          present_string(scalar(first["navn"] || first["name"]))
        else
          present_string(first)
        end
      end
    end

    def self.build_address_line(address, node)
      if address["vejnavn"]
        parts = [ scalar(address["vejnavn"]), scalar(address["husnummer"] || address["husnr"]) ]
        joined = parts.compact.map { |part| part.to_s.strip }.reject(&:empty?).join(" ")
        return present_string(joined)
      end

      present_string(scalar(node["address"] || node["adressebetegnelse"]))
    end

    def self.scalar(value)
      return nil if value.nil? || value.is_a?(Hash) || value.is_a?(Array)

      value
    end

    def self.present_string(value)
      return nil if value.nil?

      string = value.to_s.strip
      string.empty? ? nil : string
    end

    private_class_method :build_address_line, :scalar, :present_string
  end
end
