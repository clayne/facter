# frozen_string_literal: true

module Facts
  module Linux
    module Processors
      class Extensions
        FACT_NAME = 'processors.extensions'

        def call_the_resolver
          fact_value = Facter::Resolvers::Linux::Processors.resolve(:extensions)
          Facter::ResolvedFact.new(FACT_NAME, fact_value)
        end
      end
    end
  end
end
