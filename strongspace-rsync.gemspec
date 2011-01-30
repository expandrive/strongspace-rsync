$:.unshift File.expand_path("../lib", __FILE__)
require "strongspace-rsync/version"

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

  gem.add_development_dependency "rake"
  gem.add_development_dependency "ZenTest"
  gem.add_development_dependency "autotest-growl"
  gem.add_development_dependency "autotest-fsevent"
  gem.add_development_dependency "rspec",   "~> 1.3.0"
  gem.add_development_dependency "webmock", "~> 1.5.0"
  gem.add_development_dependency "ruby-fsevent"
  gem.add_development_dependency "strongspace", "~> 0.2.0"
end
