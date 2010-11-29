Gem::Specification.new do |s|
  s.name    = 'love'

  # Do not change the version and date fields by hand. This will be done
  # automatically by the gem release script.
  s.version = "0.0.1"
  s.date    = "2010-11-29"

  s.summary     = "Ruby library to access the Tender REST API."
  s.description = <<-EOT
    A simple API wrapper for Tender, that handles paged results, uses yajl-ruby for
    JSON parsing, and manually handles UTF-8 encoding to circumvent the invalid UTF-8
    character problem in Ruby 1.9.
  EOT

  s.authors  = ['Willem van Bergen']
  s.email    = ['willem@railsdoctors.com']
  s.homepage = 'http://github.com/wvanbergen/love'

  s.add_runtime_dependency('activesupport')
  s.add_runtime_dependency('yajl-ruby')

  s.add_development_dependency('rake')
  # s.add_development_dependency('rspec', '~> 2.1')

  s.rdoc_options << '--title' << s.name << '--main' << 'README.rdoc' << '--line-numbers' << '--inline-source'
  s.extra_rdoc_files = ['README.rdoc']

  # Do not change the files and test_files fields by hand. This will be done
  # automatically by the gem release script.
  s.files      = %w()
  s.test_files = %w()
end
