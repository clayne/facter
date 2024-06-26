# frozen_string_literal: true

module Facter
  module Resolvers
    class PosxIdentity < BaseResolver
      init_resolver

      class << self
        private

        def post_resolve(fact_name, _options)
          @fact_list.fetch(fact_name) { retrieve_identity(fact_name) }
        end

        def retrieve_identity(fact_name)
          require 'etc'

          login_info = Etc.getpwuid
          @fact_list[:gid] = login_info.gid
          @fact_list[:group] = Etc.getgrgid(login_info.gid).name
          @fact_list[:privileged] = login_info.uid.zero?
          @fact_list[:uid] = login_info.uid
          @fact_list[:user] = login_info.name
          @fact_list[fact_name]
        end
      end
    end
  end
end
