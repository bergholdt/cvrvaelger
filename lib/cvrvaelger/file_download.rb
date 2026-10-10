# frozen_string_literal: true

module Cvrvaelger
  # Metadata for a Datafordeler CVR totaldownload zip (no local unzipping).
  FileDownload = Data.define(
    :file_name,
    :register,
    :entity_name,
    :type_of_download,
    :type_of_data,
    :contained_file_format,
    :output_file_format,
    :generation_number,
    :file_size_in_bytes,
    :md5_hash,
    :generation_time,
    :expiration_date
  ) do
    def self.from_node(node)
      new(
        file_name: present_string(node["fileName"]),
        register: present_string(node["register"]),
        entity_name: present_string(node["entityName"]),
        type_of_download: present_string(node["typeOfDownload"]),
        type_of_data: present_string(node["typeOfData"]),
        contained_file_format: present_string(node["containedFileFormat"]),
        output_file_format: present_string(node["outputFileFormat"]),
        generation_number: node["generationNumber"],
        file_size_in_bytes: node["fileSizeInBytes"],
        md5_hash: present_string(node["md5Hash"]),
        generation_time: present_string(node["generationTime"]),
        expiration_date: present_string(node["expirationDate"])
      )
    end

    def self.present_string(value)
      return nil if value.nil?

      string = value.to_s.strip
      string.empty? ? nil : string
    end

    private_class_method :present_string
  end
end
