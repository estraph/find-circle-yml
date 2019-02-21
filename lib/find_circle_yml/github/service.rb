# frozen_string_literal: true

require "base64"
require "httparty"
require "yaml"

module FindCircleYml
  module GitHub
    class Service
      attr_reader :user, :access_token, :organization

      def initialize(user, access_token, organization)
        @user = user
        @access_token = access_token
        @organization = organization
      end

      def repositories
        all_repos = client.organization_repositories(organization)
        not_archived = all_repos.select{ |r| r[:archived] == false }
        puts "found #{not_archived.count} unarchived repos in the organization"

        uses_circle = not_archived.select do |r|
          count = recent_circle_build_count(r[:full_name])
          count > 0
        end
        puts "inspecting #{uses_circle.count} of #{not_archived.count} unarchived organization repos"
        uses_circle.map do |response|
          return unless recent_circle_build_count(response[:full_name]) > 0
          Repository.new(
            response[:full_name],
            response[:default_branch],
            response[:html_url]
          )
        end
      end

      def recent_circle_build_count(full_name)
        # https://circleci.com/docs/api/#getting-started
        # /project/:vcs-type/:username/:project
        # lists up to 30 recent builds for the project
        token = ENV['CIRCLECI_TOKEN']
        response = HTTParty.get("https://circleci.com/api/v1.1/project/github/#{full_name}?circle-token=#{token}")
        return 0 unless response.code == 200
        return JSON.parse(response.body).count
      end

      def configuration_file_content(repository, path)
        client.contents(repository.name, path: path)
      rescue Octokit::NotFound
        nil
      end

      def configuration_files(repository)
        ['circle.yml', '.circleci/config.yml'].map do |path|
          content = configuration_file_content(repository, path)
          present = !content.nil?
          version = YAML.load(Base64.decode64(content[:content]))["version"] if present
          ConfigurationFile.new(path, present, version)
        end
      end

      private

      def client
        Octokit.auto_paginate = true
        Octokit::Client.new(login: user, password: access_token)
      end
    end
  end
end
