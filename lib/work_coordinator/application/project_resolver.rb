# frozen_string_literal: true

module WorkCoordinator
  module Application
    # Resolves a free-form project query to a {Domain::Project} using a tiered
    # match strategy: exact name/alias first, then fuzzy substring matching with
    # ambiguity detection when multiple candidates qualify.
    class ProjectResolver
      # Result of a resolution attempt.
      #
      # @!attribute [r] status
      #   @return [Symbol] :found, :ambiguous, or :not_found
      # @!attribute [r] project
      #   @return [Domain::Project, nil] the matched project when status is :found
      # @!attribute [r] candidates
      #   @return [Array<Domain::Project>] competing matches when status is :ambiguous
      Result = Data.define(:status, :project, :candidates) do
        # @return [Boolean]
        def found?     = status == :found

        # @return [Boolean]
        def ambiguous? = status == :ambiguous

        # @return [Boolean]
        def not_found? = status == :not_found
      end

      # @param project_repo [Ports::ProjectRepository]
      def initialize(project_repo:)
        @project_repo = project_repo
      end

      # @param query [String, nil]
      # @return [Result]
      def resolve(query)
        return not_found_result if query.nil? || query.strip.empty?

        exact = @project_repo.find_by_name_or_alias(query)
        return Result.new(status: :found, project: exact, candidates: []) if exact

        fuzzy = fuzzy_candidates(query)
        case fuzzy.size
        when 0 then not_found_result
        when 1 then Result.new(status: :found, project: fuzzy.first, candidates: [])
        else        Result.new(status: :ambiguous, project: nil, candidates: fuzzy)
        end
      end

      private

      def not_found_result
        Result.new(status: :not_found, project: nil, candidates: [])
      end

      def fuzzy_candidates(query) # rubocop:disable Metrics/AbcSize
        needle = normalize(query.downcase.strip)
        @project_repo.find_all.select do |p|
          name_norm  = normalize(p.name.downcase)
          alias_norm = p.alias ? normalize(p.alias.downcase) : ""
          name_norm.include?(needle) || needle.include?(name_norm) ||
            (!alias_norm.empty? && (alias_norm.include?(needle) || needle.include?(alias_norm)))
        end
      end

      def normalize(str)
        str.gsub("-", "_")
      end
    end
  end
end
