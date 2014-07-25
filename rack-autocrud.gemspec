Gem::Specification.new do |gem|
  gem.name        = 'rack-autocrud'
  gem.version     = '0.1.21'
  gem.author      = 'Tim Hentenaar'
  gem.email       = 'tim.hentenaar@gmail.com'
  gem.homepage    = 'https://github.com/thentenaar/rack-autocrud'
  gem.summary     = 'Rack middleware that automagically handles basic CRUD operations'
  gem.description = <<__XXX__
  Rack middleware that works with Sinatra to dynamically create CRUD
  endpoints and routes based on models. It ain't perfect, but it works.

  These generated CRUD routes are assumed to return a Rack response.

  It's important to note, that you models and endpoints must be in
  separate modules (read: namespaces).

  Input and Response data are formatted as JSON.

  See the README for more info.
__XXX__

  gem.files = Dir['lib/**/*','README*', 'LICENSE']
  gem.add_dependency 'json'
  gem.add_dependency 'sinatra'
end

# vi:set ts=2 sw=2 expandtab sta:
