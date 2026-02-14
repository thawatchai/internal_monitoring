# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name        = 'internal_monitoring'
  spec.version     = '0.1.0'
  spec.authors     = ['Usable Labs']
  spec.summary     = 'Shared error monitoring engine for Rails apps'

  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{app,config,lib}/**/*', 'Gemfile', '*.gemspec']
  end

  spec.add_dependency 'rails', '>= 7.0'
end
