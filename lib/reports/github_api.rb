require 'faraday'
require 'json'

module Reports

  Event = Struct.new(:type, :repo_name)
  Repo = Struct.new(:name, :languages)
  Gist = Struct.new(:url)

  class GitHubAPI

    class RequestFailure < StandardError
      def initialize(response)
        method = response.env.method.to_s.upcase
        url = response.env.url.to_s
        message = "#{method} to #{url} returned #{response.status}\n" + response.body

        super message
      end
    end

    def initialize(token)
      @token = token
    end

    def public_events_for_user(username)
      url = "https://api.github.com/users/#{username}/events/public"
      events = request_all_pages(url)

      events.map do |event|
        Event.new(event["type"], event["repo"]["name"])
      end
    end

    def public_repos_for_user(username, options={})
      url = "https://api.github.com/users/#{username}/repos"
      repos = request_all_pages(url)

      repos.map do |repo|
        next if !options[:forks] && repo["fork"]

        full_name = repo["full_name"]
        language_url = "https://api.github.com/repos/#{full_name}/languages"

        response = perform_request(:get, language_url)

        Repo.new(repo["name"], JSON.parse(response.body))
      end.compact
    end

    def create_private_gist(description, filename, contents)
      url = "https://api.github.com/gists"
      payload = JSON.dump({
        description: description,
        public: false,
        files: {
          filename => {
            content: contents
          }
        }
      })

      response = perform_request(:post, url, params: payload)

      gist = JSON.parse(response.body)
      Gist.new(gist["html_url"])
    end

    def repo_starred?(full_repo_name)
      url = "https://api.github.com/user/starred/#{full_repo_name}"
      response = perform_request(:get, url, statuses: [204, 404])
      response.status == 204
    end

    def star_repo(full_repo_name)
      url = "https://api.github.com/user/starred/#{full_repo_name}"
      perform_request(:put, url, statuses: 204)
    end

    def unstar_repo(full_repo_name)
      url = "https://api.github.com/user/starred/#{full_repo_name}"
      perform_request(:delete, url, statuses: 204)
    end

    private

    def client
      @client ||= Faraday::Connection.new do |builder|
        builder.use LoggingMiddleware
        builder.adapter Faraday.default_adapter
      end
    end

    def request_all_pages(url)
      results = []

      while url do
        response = perform_request(:get, url)

        results.concat(JSON.parse(response.body))
        url = extract_next_page_url(response)
      end

      results
    end

    def perform_request(method, url, options={})
      params_or_body = options.fetch(:params, nil)
      statuses = Array(options.fetch(:statuses, [200, 201]))

      raise ArgumentError unless %i{get post put delete}.include?(method)
      headers = {"Authorization" => "token #{@token}"}

      response = client.send(method, url, params_or_body, headers)

      raise RequestFailure.new(response) unless statuses.include?(response.status)

      response
    end

    def extract_next_page_url(response)
      link_header = response.headers['link']
      return nil unless link_header

      next_page = link_header.split(',').find{|h| h =~ %r{rel="next"}}
      return nil unless next_page

      URI.extract(next_page).first
    end

  end
end
