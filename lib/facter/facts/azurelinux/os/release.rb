# frozen_string_literal: true

module Facts
  module Azurelinux
    module Os
      class Release
        FACT_NAME = 'os.release'
        ALIASES = %w[operatingsystemmajrelease operatingsystemrelease].freeze

        def call_the_resolver
          version = from_specific_file || from_os_release

          return Facter::ResolvedFact.new(FACT_NAME, nil) unless version

          [Facter::ResolvedFact.new(FACT_NAME, version),
           Facter::ResolvedFact.new(ALIASES.first, version['major'], :legacy),
           Facter::ResolvedFact.new(ALIASES.last, version['full'], :legacy)]
        end

        def from_specific_file
          version = Facter::Resolvers::SpecificReleaseFile.resolve(:release,
                                                                   { release_file: '/etc/azurelinux-release',
                                                                     regex: /AZURELINUX_BUILD_NUMBER=([0-9.]+)/ })
          Facter::Util::Facts.release_hash_from_matchdata(version)
        end

        def from_os_release
          version = Facter::Resolvers::OsRelease.resolve(:version_id)

          Facter::Util::Facts.release_hash_from_string(version)
        end
      end
    end
  end
end
