require 'octokit'
require 'json'
require 'open-uri'
require 'digest'

# Initialize GitHub client
client = Octokit::Client.new(access_token: ENV['GITHUB_TOKEN'])

begin
  # Get latest release from upstream
  latest_release = client.latest_release('philippe44/AirConnect')
  latest_version = latest_release.tag_name
  
  puts "🔍 Latest upstream version: #{latest_version}"
  
  # Check if we have a record of the last processed version
  last_version_file = '.last_version'
  last_processed_version = File.exist?(last_version_file) ? File.read(last_version_file).strip : nil
  
  puts "📋 Last processed version: #{last_processed_version || 'none'}"
  
  # Check if update is needed
  if latest_version != last_processed_version
    puts "🔄 Update needed: #{last_processed_version || 'none'} -> #{latest_version}"
    
    # Download the new release to get SHA256
    download_url = "https://github.com/philippe44/AirConnect/releases/download/#{latest_version}/AirConnect-#{latest_version}.zip"
    puts "⬇️  Downloading: #{download_url}"
    
    begin
      file_content = URI.open(download_url, 'User-Agent' => 'GitHub-Actions').read
      sha256 = Digest::SHA256.hexdigest(file_content)
      file_size = (file_content.length / 1024.0 / 1024.0).round(2)
      
      puts "✅ Download successful"
      puts "📏 File size: #{file_size} MB"
      puts "🔐 SHA256: #{sha256}"
      
      # Get release information
      release_date = latest_release.published_at.strftime('%Y-%m-%d')
      release_body = latest_release.body || "No release notes available"
      
      # Output for GitHub Actions
      File.open(ENV['GITHUB_OUTPUT'], 'a') do |f|
        f.puts "update_needed=true"
        f.puts "new_version=#{latest_version}"
        f.puts "new_sha256=#{sha256}"
        f.puts "download_url=#{download_url}"
        f.puts "file_size=#{file_size}"
        f.puts "release_date=#{release_date}"
        f.puts "release_notes<<EOF"
        f.puts release_body
        f.puts "EOF"
      end
      
      # Update last processed version
      File.write(last_version_file, latest_version)
      
    rescue => e
      puts "❌ Failed to download or process release: #{e.message}"
      exit 1
    end
  else
    puts "✅ No update needed - already at latest version"
    File.open(ENV['GITHUB_OUTPUT'], 'a') do |f|
      f.puts "update_needed=false"
    end
  end
  
rescue => e
  puts "❌ Error checking for updates: #{e.message}"
  exit 1
end
