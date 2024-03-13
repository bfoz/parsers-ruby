lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
    spec.name          = "parsers"
    spec.version       = '0.1'
    spec.authors       = ["Brandon Fosdick"]
    spec.email         = ["bfoz@bfoz.net"]

    spec.summary       = 'Various parsers written in Ruby'
    spec.description   = 'A collection of parser implementations'
    spec.homepage      = 'https://github.com/bfoz/parsers-ruby'
    spec.license       = '0BSD'

    spec.files         = `git ls-files -z`.split("\x0").reject do |f|
	f.match(%r{^(test|spec|features)/})
    end
    spec.bindir        = "bin"
    spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
    spec.require_paths = ["lib"]

    spec.add_development_dependency "bundler", "~> 2"
    spec.add_development_dependency "rake", "~> 10.0"
    spec.add_development_dependency "rspec", "~> 3.0"
end
