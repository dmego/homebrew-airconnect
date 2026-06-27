#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open-uri"
require "pathname"
require "time"

class AirconnectReleaseUpdater
  UPSTREAM_REPO = "philippe44/AirConnect"
  FORMULA_FILE = "Formula/airconnect.rb"
  MANAGER_FILE = "scripts/airconnect-manager.sh"
  CHANGELOG_FILE = "CHANGELOG.md"
  DOWNLOAD_CHUNK_SIZE = 1024 * 1024
  OPEN_TIMEOUT_SECONDS = 30
  READ_TIMEOUT_SECONDS = 60
  OUTPUT_DELIMITER_RANGE = 1_000_000

  Release = Struct.new(
    :version,
    :sha256,
    :download_url,
    :file_size,
    :release_date,
    :release_notes,
    keyword_init: true
  )

  def initialize(env = ENV)
    @env = env
    @root = Pathname(env.fetch("AIRCONNECT_UPDATER_ROOT", Dir.pwd))
    @repo = env.fetch("UPSTREAM_REPO", UPSTREAM_REPO)
    @formula_path = @root / env.fetch("FORMULA_FILE", FORMULA_FILE)
    @manager_path = @root / MANAGER_FILE
    @changelog_path = @root / CHANGELOG_FILE
  end

  def run
    release = offline? ? offline_release : latest_release
    current_version = read_current_formula_version
    current_sha256 = read_current_formula_sha256
    update_needed = current_version != release.version || current_sha256 != release.sha256

    if update_needed
      update_formula(release)
      update_manager(release)
      update_changelog(current_version, release)
      verify_final_state(release)
    end

    write_outputs(current_version, release, update_needed)
  end

  private

  def offline?
    @env["AIRCONNECT_UPDATER_OFFLINE"] == "1"
  end

  def offline_release
    version = @env.fetch("AIRCONNECT_UPDATER_VERSION")
    Release.new(
      version: version,
      sha256: @env.fetch("AIRCONNECT_UPDATER_SHA256"),
      download_url: release_download_url(version),
      file_size: @env.fetch("AIRCONNECT_UPDATER_FILE_SIZE", "0"),
      release_date: @env.fetch("AIRCONNECT_UPDATER_RELEASE_DATE", Time.now.utc.strftime("%Y-%m-%d")),
      release_notes: @env.fetch("AIRCONNECT_UPDATER_RELEASE_NOTES", "")
    )
  end

  def latest_release
    release = read_json("https://api.github.com/repos/#{@repo}/releases/latest")
    version = release.fetch("tag_name")
    asset = release.fetch("assets").find { |item| item["name"] == "AirConnect-#{version}.zip" }
    raise "Release #{version} does not contain AirConnect-#{version}.zip" unless asset

    digest, bytesize = digest_download(asset.fetch("browser_download_url"))
    Release.new(
      version: version,
      sha256: digest,
      download_url: asset.fetch("browser_download_url"),
      file_size: format("%.2f", bytesize / 1024.0 / 1024.0),
      release_date: Time.parse(release.fetch("published_at")).strftime("%Y-%m-%d"),
      release_notes: release["body"].to_s
    )
  end

  def digest_download(url)
    digest = Digest::SHA256.new
    bytesize = 0

    URI.open(url, request_options) do |io|
      while (chunk = io.read(DOWNLOAD_CHUNK_SIZE))
        bytesize += chunk.bytesize
        digest.update(chunk)
      end
    end

    [digest.hexdigest, bytesize]
  end

  def read_json(url)
    JSON.parse(URI.open(url, request_options).read)
  end

  def request_options
    headers = { "User-Agent" => "homebrew-airconnect-updater" }
    token = @env["GITHUB_TOKEN"]
    headers["Authorization"] = "Bearer #{token}" unless token.to_s.empty?
    headers.merge(open_timeout: OPEN_TIMEOUT_SECONDS, read_timeout: READ_TIMEOUT_SECONDS)
  end

  def read_current_formula_version
    formula.match(%r{releases/download/([^/]+)/AirConnect-[^/]+\.zip})&.captures&.first ||
      raise("Could not determine current Formula version from URL")
  end

  def read_current_formula_sha256
    formula.match(/^\s*sha256 "([^"]+)"$/)&.captures&.first ||
      raise("Could not determine current Formula sha256")
  end

  def formula
    @formula ||= @formula_path.read
  end

  def update_formula(release)
    content = formula.dup
    expected_url = release_download_url(release.version)

    replace_once!(
      content,
      /^  url "https:\/\/github\.com\/#{Regexp.escape(@repo)}\/releases\/download\/[^"]+\/AirConnect-[^"]+\.zip"$/,
      %(  url "#{expected_url}"),
      "Formula URL"
    )
    replace_once!(
      content,
      /^  sha256 "[^"]+"$/,
      %(  sha256 "#{release.sha256}"),
      "Formula sha256"
    )

    @formula_path.write(content)
    @formula = content
  end

  def update_manager(release)
    return unless @manager_path.exist?

    content = @manager_path.read
    replace_once!(
      content,
      /^AIRCONNECT_VERSION="[^"]+"$/,
      %(AIRCONNECT_VERSION="#{release.version}"),
      "manager AirConnect version"
    )
    @manager_path.write(content)
  end

  def update_changelog(current_version, release)
    content = @changelog_path.exist? ? @changelog_path.read : "# Changelog\n"
    content = "# Changelog\n#{content.sub(/\A# Changelog\s*/, "\n")}" unless content.start_with?("# Changelog")
    return if changelog_entry_count(content, release.version).positive?

    entry = [
      "## [#{release.version}] - #{release.release_date}",
      changelog_marker(release.version),
      "",
      "### Updated",
      "- AirConnect from version #{current_version} to #{release.version}",
      "- File size: #{release.file_size} MB",
      "- SHA256: #{release.sha256}",
      "",
      "### Release Notes",
      release.release_notes.to_s,
      ""
    ].join("\n")

    body = content.sub(/\A# Changelog\s*/, "").sub(/\A\n+/, "")
    @changelog_path.write("# Changelog\n\n#{entry}\n#{body}")
  end

  def verify_final_state(release)
    refreshed_formula = @formula_path.read
    expected_url = release_download_url(release.version)
    raise "Formula URL was not updated to #{release.version}" unless refreshed_formula.include?(%(url "#{expected_url}"))
    raise "Formula sha256 was not updated" unless refreshed_formula.include?(%(sha256 "#{release.sha256}"))

    if @manager_path.exist?
      manager = @manager_path.read
      raise "Manager version was not updated" unless manager.include?(%(AIRCONNECT_VERSION="#{release.version}"))
    end

    if @changelog_path.exist?
      count = changelog_entry_count(@changelog_path.read, release.version)
      raise "Changelog contains duplicate #{release.version} entries" unless count == 1
    end
  end

  def changelog_entry_count(content, version)
    content.scan(/^#{Regexp.escape(changelog_marker(version))}$/).count
  end

  def changelog_marker(version)
    "<!-- airconnect-updater:version=#{version} -->"
  end

  def replace_once!(content, pattern, replacement, label)
    count = content.scan(pattern).count
    raise "Could not find #{label} to update" if count.zero?
    raise "Found multiple #{label} entries" if count > 1

    content.sub!(pattern, replacement)
  end

  def write_outputs(current_version, release, update_needed)
    outputs = {
      "update_needed" => update_needed.to_s,
      "current_version" => current_version,
      "new_version" => release.version,
      "new_sha256" => release.sha256,
      "download_url" => release.download_url,
      "file_size" => release.file_size,
      "release_date" => release.release_date,
      "release_notes" => release.release_notes,
      "release_notes_block" => markdown_blockquote(release.release_notes)
    }

    output_path = @env["GITHUB_OUTPUT"]
    if output_path.to_s.empty?
      outputs.each { |key, value| puts "#{key}=#{value}" unless key == "release_notes" }
      return
    end

    File.open(output_path, "a") do |file|
      outputs.each { |key, value| write_output_value(file, key, value) }
    end
  end

  def write_output_value(file, key, value)
    if value.to_s.include?("\n")
      delimiter = "AIRCONNECT_OUTPUT_#{rand(OUTPUT_DELIMITER_RANGE)}"
      file.puts "#{key}<<#{delimiter}"
      file.puts value
      file.puts delimiter
      return
    end

    file.puts "#{key}=#{value}"
  end

  def markdown_blockquote(text)
    body = text.to_s.empty? ? "No release notes provided." : text.to_s
    body.lines.map { |line| "> #{line.rstrip}" }.join("\n")
  end

  def release_download_url(version)
    "https://github.com/#{@repo}/releases/download/#{version}/AirConnect-#{version}.zip"
  end
end

AirconnectReleaseUpdater.new.run
