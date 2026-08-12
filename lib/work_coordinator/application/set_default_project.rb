# frozen_string_literal: true

module WorkCoordinator
  module Application
    # Sets the default project by resolving a name-or-alias query, then calling
    # {Ports::ProjectRepository#set_default} in a transaction.
    class SetDefaultProject
      # @!attribute [r] success [Boolean]
      # @!attribute [r] project [Domain::Project, nil]
      # @!attribute [r] message [String]
      # @!attribute [r] failure_reason [Symbol, nil]
      Result = Data.define(:success, :project, :message, :failure_reason)

      # @param project_repo [Ports::ProjectRepository]
      # @param project_resolver [Application::ProjectResolver]
      def initialize(project_repo:, project_resolver:)
        @project_repo     = project_repo
        @project_resolver = project_resolver
      end

      # @param query [String]
      # @return [Result]
      def call(query:) # rubocop:disable Metrics/AbcSize
        resolution = @project_resolver.resolve(query)

        if resolution.found?
          project = @project_repo.set_default(resolution.project)
          display = project.alias ? "#{project.alias} (#{project.name})" : project.name
          Result.new(success: true, project: project,
                     message: "Default project set to #{display}", failure_reason: nil)
        elsif resolution.ambiguous?
          names = resolution.candidates.map { |p| p.alias || p.name }.join(", ")
          Result.new(success: false, project: nil,
                     message: "Ambiguous: matched #{names}. Be more specific.", failure_reason: :ambiguous)
        else
          Result.new(success: false, project: nil,
                     message: "No project found matching: #{query}", failure_reason: :not_found)
        end
      end
    end
  end
end
