# frozen_string_literal: true

module Facter
  module Resolvers
    class Gce < BaseResolver
      init_resolver

      METADATA_URL = 'http://metadata.google.internal/computeMetadata/v1/?recursive=true&alt=json'
      HEADERS = { "Metadata-Flavor": 'Google', "Accept": 'application/json' }.freeze

      class << self
        private

        def post_resolve(fact_name, _options)
          log.debug('reading Gce metadata')
          @fact_list.fetch(fact_name) { read_facts(fact_name) }
        end

        def read_facts(fact_name)
          @fact_list[:metadata] = query_for_metadata
          @fact_list[fact_name]
        end

        def query_for_metadata
          gce_data = extract_to_hash(Facter::Util::Resolvers::Http.get_request(METADATA_URL, HEADERS, {}, false))
          parse_instance(gce_data)

          gce_data.empty? ? nil : gce_data
        end

        def extract_to_hash(metadata)
          JSON.parse(metadata)
        rescue JSON::ParserError => e
          log.debug("Trying to parse result but got: #{e.message}")
          {}
        end

        def parse_instance(gce_data)
          instance_data = gce_data['instance']
          return if instance_data.nil? || instance_data.empty?

          # See https://cloud.google.com/compute/docs/metadata for information about these values
          %w[sshKeys ssh-keys].each do |name|
            keys = gce_data.dig('project', 'attributes', name)
            gce_data['project']['attributes'][name] = keys.strip.split("\n") if keys

            keys = instance_data.dig('attributes', name)
            instance_data['attributes'][name] = keys.strip.split("\n") if keys
          end

          %w[image machineType zone].each do |key|
            instance_data[key] = instance_data[key].split('/').last if instance_data[key]
          end

          network = instance_data.dig('networkInterfaces', 0, 'network')
          instance_data['networkInterfaces'][0]['network'] = network.split('/').last unless network.nil?

          gce_data['instance'] = instance_data
        end
      end
    end
  end
end
