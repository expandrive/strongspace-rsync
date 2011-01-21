$:.unshift File.expand_path("../lib", __FILE__)
require "version"

Gem::Specification.new do |gem|
  gem.name    = "strongspace-rsync"
  gem.version = StrongspaceRsync::VERSION

  gem.author   = "Strongspace"
  gem.email    = "support@strongspace.com"
  gem.homepage = "https://www.strongspace.com/"

  gem.summary     = "Rsync Backup plugin for Strongspace."
  gem.description = "Rsync Backup plugin for Strongspace gem and command=line tool"
  gem.homepage    = "http://github.com/expandrive/strongspace-rsync"

  gem.files = Dir["**/*"].select { |d| d =~ %r{^(README|bin/|data/|ext/|lib/|spec/|test/)} }

  gem.add_dependency "strongspace", "~> 0.2.0"

end
