# frozen_string_literal: true

# Aggregates provide a mechanism for facts to be resolved in multiple steps.
#
# Aggregates are evaluated in two parts: generating individual chunks and then
# aggregating all chunks together. Each chunk is a block of code that generates
# a value, and may depend on other chunks when it runs. After all chunks have
# been evaluated they are passed to the aggregate block as Hash<name, result>.
# The aggregate block converts the individual chunks into a single value that is
# returned as the final value of the aggregate.
#
# @api public
# @since 2.0.0
module Facter
  module Core
    class Aggregate
      include LegacyFacter::Core::Suitable
      include LegacyFacter::Core::Resolvable

      # @!attribute [r] name
      #
      # @return [Symbol] The name of the aggregate resolution
      #
      # @api public
      attr_reader :name

      # @!attribute [r] fact_type
      #
      # @return [Symbol] The fact type of the aggregate resolution
      #
      # @api private
      attr_reader :fact_type

      # @!attribute [r] deps
      #
      # @return [LegacyFacter::Core::DirectedGraph]
      #
      # @api private
      attr_reader :deps

      # @!attribute [r] confines
      #
      # @return [Array<LegacyFacter::Core::Confine>] An array of confines restricting
      #  this to a specific platform
      #
      # @api private
      attr_reader :confines

      # @!attribute [r] fact
      #
      # @return [Facter::Util::Fact]
      #
      # @api private
      attr_reader :fact

      # @!attribute [r] last_evaluated
      #
      # @return [String]
      #
      # @api public
      attr_reader :last_evaluated

      # Create a new aggregated resolution mechanism.
      #
      # @param name [String] The name of the resolution.
      # @param fact [Facter::Fact] The fact to which this
      #             resolution will be added.
      #
      # @return [Facter::Util::Resolution] The created resolution
      #
      # @api private
      def initialize(name, fact)
        @name = name
        @fact = fact

        @confines = []
        @chunks = {}

        @aggregate = nil
        @deps = LegacyFacter::Core::DirectedGraph.new
      end

      # Compares the weight of two aggregate facts
      #
      # @return [bool] Weight comparison result
      #
      # @api private
      def <=>(other)
        weight <=> other.weight
      end

      # Sets options for the aggregate fact
      #
      # @return [nil]
      #
      # @api private
      def options(options)
        accepted_options = %i[name timeout weight fact_type]
        accepted_options.each do |option_name|
          instance_variable_set("@#{option_name}", options.delete(option_name)) if options.key?(option_name)
        end
        raise ArgumentError, "Invalid aggregate options #{options.keys.inspect}" unless options.keys.empty?
      end

      # Evaluates the given block
      #
      # @return [String] Result of the block's evaluation
      #
      # @api private
      def evaluate(&block)
        if @last_evaluated
          msg = +"Already evaluated #{@name}"
          msg << " at #{@last_evaluated}" if msg.is_a? String
          msg << ', reevaluating anyways'
          log.warn msg
        end
        instance_eval(&block)

        @last_evaluated = block.source_location.join(':')
      end

      # Define a new chunk for the given aggregate
      #
      # @example Defining a chunk with no dependencies
      #   aggregate.chunk(:mountpoints) do
      #     # generate mountpoint information
      #   end
      #
      # @example Defining an chunk to add mount options
      #   aggregate.chunk(:mount_options, :require => [:mountpoints]) do |mountpoints|
      #     # `mountpoints` is the result of the previous chunk
      #     # generate mount option information based on the mountpoints
      #   end
      #
      # @param name [Symbol] A name unique to this aggregate describing the chunk
      #
      # @param opts [Hash] Hash with options for the aggregate fact
      #
      # @return [Facter::Core::Aggregate] The aggregate object
      #
      # @api public
      def chunk(name, opts = {}, &block)
        evaluate_params(name, &block)

        deps = Array(opts.delete(:require))

        unless opts.empty?
          raise ArgumentError, "Unexpected options passed to #{self.class.name}#chunk: #{opts.keys.inspect}"
        end

        @deps[name] = deps
        @chunks[name] = block
        self
      end

      # Define how all chunks should be combined
      #
      # @example Merge all chunks
      #   aggregate.aggregate do |chunks|
      #     final_result = {}
      #     chunks.each_value do |chunk|
      #       final_result.deep_merge(chunk)
      #     end
      #     final_result
      #   end
      #
      # @example Sum all chunks
      #   aggregate.aggregate do |chunks|
      #     total = 0
      #     chunks.each_value do |chunk|
      #       total += chunk
      #     end
      #     total
      #   end
      #
      # @yield [Hash<Symbol, Object>] A hash containing chunk names and
      #   chunk values
      #
      # @return [Facter::Core::Aggregate] The aggregate fact
      #
      # @api public
      def aggregate(&block)
        raise ArgumentError, "#{self.class.name}#aggregate requires a block" unless block_given?

        @aggregate = block
        self
      end

      # Returns the fact's resolution type
      #
      # @return [Symbol] The fact's type
      #
      # @api private
      def resolution_type
        :aggregate
      end

      private

      def log
        @log ||= Facter::Log.new(self)
      end

      def evaluate_params(name)
        raise ArgumentError, "#{self.class.name}#chunk requires a block" unless block_given?
        raise ArgumentError, "#{self.class.name}#expected chunk name to be a Symbol" unless name.is_a? Symbol
      end

      # Evaluate the results of this aggregate.
      #
      # @see Facter::Core::Resolvable#value
      # @return [Object]
      def resolve_value
        chunk_results = run_chunks
        aggregate_results(chunk_results)
      end

      # Order all chunks based on their dependencies and evaluate each one, passing
      # dependent chunks as needed.
      #
      # @return [Hash<Symbol, Object>] A hash containing the chunk that
      #   generated value and the related value.
      def run_chunks
        results = {}
        order_chunks.each do |(name, block)|
          input = @deps[name].map { |dep_name| results[dep_name] }

          output = block.call(*input)
          results[name] = LegacyFacter::Util::Values.deep_freeze(output)
        end

        results
      end

      # Process the results of all chunks with the aggregate block and return the
      # results. If no aggregate block has been specified, fall back to deep
      # merging the given data structure
      #
      # @param results [Hash<Symbol, Object>] A hash of chunk names and the output
      #   of that chunk.
      # @return [Object]
      def aggregate_results(results)
        if @aggregate
          @aggregate.call(results)
        else
          default_aggregate(results)
        end
      end

      def default_aggregate(results)
        results.values.inject do |result, current|
          LegacyFacter::Util::Values.deep_merge(result, current)
        end
      rescue LegacyFacter::Util::Values::DeepMergeError => e
        raise ArgumentError, 'Could not deep merge all chunks (Original error: ' \
                         "#{e.message}), ensure that chunks return either an Array or Hash or " \
                         'override the aggregate block', e.backtrace
      end

      # Order chunks based on their dependencies
      #
      # @return [Array<Symbol, Proc>] A list of chunk names and blocks in evaluation order.
      def order_chunks
        unless @deps.acyclic?
          raise DependencyError,
                "Could not order chunks; found the following dependency cycles: #{@deps.cycles.inspect}"
        end

        sorted_names = @deps.tsort

        sorted_names.map do |name|
          [name, @chunks[name]]
        end
      end

      class DependencyError < StandardError; end
    end
  end
end
