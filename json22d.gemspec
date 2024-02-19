# frozen_string_literal: true
$LOAD_PATH.push File.expand_path("../lib", __FILE__)

require "json22d"

Gem::Specification.new do |s|
  s.name = "json22d"
  s.version = JSON22d::VERSION
  s.summary = "Transpile JSON into a flat structure"
  s.description = "Create CSV/XSLX formats and many others with this transpiler"
  s.authors = ["Matthias Geier"]
  s.homepage = "https://github.com/metoda/json22d"
  s.license = "BSD-2-Clause"
  s.files = Dir["lib/**/*"]
  s.test_files = Dir["spec/**/*"]
  s.add_dependency "activesupport", " > 3"
  s.add_dependency "oj"
  s.add_development_dependency "minitest", "~> 5"
end
