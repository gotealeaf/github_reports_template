require 'faraday'
require 'json'

module Reports

  Event = Struct.new(:type, :repo_name)
  Repo = Struct.new(:name, :languages)

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

        response = perform_request(language_url)

        Repo.new(repo["name"], JSON.parse(response.body))
      end.compact
    end

    private

    def request_all_pages(url)
      results = []

      while url do
        response = perform_request(url)

        results.concat(JSON.parse(response.body))
        url = extract_next_page_url(response)
      end

      results
    end

    def perform_request(url)
      headers = {"Authorization" => "token #{@token}"}
      response = Faraday.get(url, {}, headers)
      raise RequestFailure.new(response) unless (200..299).cover?(response.status)

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
